/**
 * The contract of `dw handout`: what `dw` hands the renderer host, what the host and the builder say
 * to each other, what a page reports once it rendered, and what the host hands back to `dw`.
 *
 * Why it exists: one export crosses four programs that share no code. `scripts/dw` (bash) writes
 * input.json with jq; `handout/main.swift` (the host) renders pages in a concealed web view and
 * publishes the file; the builder (this package, built into one HTML file the host loads) checks,
 * sanitizes and assembles; `explainer/page.html` renders each page and reports. The shapes they meet
 * in are written once, here: the builder parses everything it receives against these schemas, the
 * Swift host mirrors them as Codable types, and dw reads the result with jq.
 *
 * Flow (eng review, final diagram):
 *
 * ```
 * dw ──input.json──▶ host ──build(input)──▶ builder
 *                     ▲  ◀──render / read / verify──┘   (postMessage with a reply)
 *                     │  page view: pages/NNN.html ──rendered──▶ host
 *                     └──── BuildOutcome ◀── builder;  host publishes, prints HostResult ──▶ dw
 * ```
 *
 * Codes: every failure carries one stable `HANDOUT_*` code (DX D12); SKILL.md lists each with its
 * fix, and scripts/check compares that table with the codes in the code, both ways.
 *
 * | Code | Raised by | When |
 * | --- | --- | --- |
 * | HANDOUT_EMPTY | dw | the Record has no pages |
 * | HANDOUT_RECORD | dw | the page listing changed while it was read, after one re-read |
 * | HANDOUT_MARKER | dw (explain_build) | an audience marker without its partner, with its source line |
 * | HANDOUT_VENDOR | dw, builder | a library missing or failing its digest; a library a page did not load |
 * | HANDOUT_SECRET | builder | a secret shape in a page source, a title or a section name (never the value) |
 * | HANDOUT_DIAGRAM | builder | a diagram failed to render, or has no label with a size |
 * | HANDOUT_OVERFLOW | builder | a diagram label wider than its node, with every `<details>` open |
 * | HANDOUT_IMAGE | builder | a local image that does not resolve, or an image that is not local |
 * | HANDOUT_TEMPLATE | builder | page.html lacks the markers around the CSS the Handout takes |
 * | HANDOUT_VERIFY | builder | the finished file, reopened under its own CSP, lost labels or its controller did not run |
 * | HANDOUT_RENDERER | host, dw | the host is unavailable, a time limit passed, its web content ended or the builder threw |
 * | HANDOUT_OUT_EXISTS | dw, host | the output path is a folder, holds a file that is not a Handout, or cannot be written |
 */
import { z } from 'zod'

import { HANDOUT_PROTOCOL_VERSION, PAGE_RENDER_LIMIT_MS, RUN_LIMIT_MS } from './constants'

/** Every failure code of `dw handout`; the table above says who raises each one. */
export const handoutCodeSchema = z.enum([
  'HANDOUT_EMPTY',
  'HANDOUT_RECORD',
  'HANDOUT_MARKER',
  'HANDOUT_VENDOR',
  'HANDOUT_SECRET',
  'HANDOUT_DIAGRAM',
  'HANDOUT_OVERFLOW',
  'HANDOUT_IMAGE',
  'HANDOUT_TEMPLATE',
  'HANDOUT_VERIFY',
  'HANDOUT_RENDERER',
  'HANDOUT_OUT_EXISTS',
])
export type HandoutCode = z.infer<typeof handoutCodeSchema>

/**
 * The first bytes of every Handout, ending with the tag that makes a file one
 * (`<meta name="dw-handout" content="1">`, DX D11, D16). Before replacing a file, dw and the host
 * require it to start with exactly these bytes and never replace one that does not (eng D7): the
 * marker's text elsewhere near the top (a page about Handouts, a form field, a source file) is not a
 * Handout. scripts/check requires scripts/dw and handout/main.swift to carry the same literal.
 */
export const HANDOUT_HEAD =
  '<!doctype html>\n<html lang="ja">\n<head>\n<meta charset="utf-8">\n<meta name="dw-handout" content="1">'

/** A position in the Record that a message points at; every field the cause knows, nothing more. */
const locationShape = {
  /** Page number, as in `pages/NN-*.md`. */
  page: z.number().int().positive().optional(),
  /** Line in the page's original source (before audience markers were filtered). */
  line: z.number().int().positive().optional(),
  /** Diagram on that page, counted from 1 in reading order. */
  diagram: z.number().int().positive().optional(),
}

/**
 * One reason an export stopped. Its message names a page by its number (`page 7:12`), never by its
 * file name, which dw makes from the page's title; it never contains a secret value.
 */
export const diagnosticSchema = z.object({
  code: handoutCodeSchema,
  message: z.string().min(1),
  ...locationShape,
  /** The secret pattern's name, for HANDOUT_SECRET (`github-token`); the value itself is never carried. */
  pattern: z.string().optional(),
})
export type Diagnostic = z.infer<typeof diagnosticSchema>

/** Something the agent should fix that did not stop the export (DX D10): exit 0, one line each. */
export const warningSchema = z.object({
  message: z.string().min(1),
  ...locationShape,
})
export type Warning = z.infer<typeof warningSchema>

/** One Record page as dw lists it for the export, in numeric order (DX D19). */
export const handoutPageSchema = z.object({
  n: z.number().int().positive(),
  /** Exact title: sections.tsv column 3, else the H1 of the Handout's audience, else the file name (DX D18). */
  title: z.string(),
  /** Section name from sections.tsv column 2; empty when the page has none. */
  section: z.string(),
  /**
   * The page's original source, both audiences: what the secret scan reads and where an image's line
   * is found. Line numbers in every message count lines of this text.
   */
  markdown: z.string(),
  /** Path of the page built for the Handout audience, relative to `explainDir`: `pages/007.html`. */
  built: z.string().min(1),
})
export type HandoutPage = z.infer<typeof handoutPageSchema>

/** The host's time limits (eng D3). dw always sets both; fixtures shorten them to test the limits. */
export const handoutLimitsSchema = z.object({
  pageMs: z.number().int().positive(),
  runMs: z.number().int().positive(),
  /**
   * How often the host looks whether dw's process is still there (1000 when absent). A fixture
   * lengthens it so only the look right before publishing can stop the export.
   */
  parentMs: z.number().int().positive().optional(),
})
export type HandoutLimits = z.infer<typeof handoutLimitsSchema>

/** The limits dw sets on a real export. */
export const DEFAULT_LIMITS: HandoutLimits = { pageMs: PAGE_RENDER_LIMIT_MS, runMs: RUN_LIMIT_MS }

/**
 * input.json: written by `dw handout` (jq), read by the host, handed whole to the builder.
 *
 * Paths are absolute. `explainDir` is a temporary explain folder that dw built with explain_build in
 * Handout mode: `pages/NNN.html` and a `vendor/` folder of copied (never linked) libraries, since a
 * script reached through a symlink out of the web view's read-access folder does not load.
 */
export const handoutInputSchema = z.object({
  v: z.literal(HANDOUT_PROTOCOL_VERSION),
  record: z.object({
    /** Folder name of the Record, as `dw records` lists it. */
    name: z.string().min(1),
    /** The Record's folder; relative image paths resolve against its `pages/` folder (DX D15). */
    dir: z.string().min(1),
  }),
  explainDir: z.string().min(1),
  /** explainer/page.html: the Handout takes the CSS between its markers at every export. */
  template: z.string().min(1),
  /** Where the Handout is published: `<record>/handout.html`, or the path given with `--out`. */
  out: z.string().min(1),
  /** The host's log; HANDOUT_RENDERER names it. */
  log: z.string().min(1),
  limits: handoutLimitsSchema,
  /**
   * dw's process. The host stops without publishing once it is gone (dw killed, its terminal closed):
   * nobody waits for that export. Absent when the host is run by hand or by a check.
   */
  parentPid: z.number().int().positive().optional(),
  /** At least one page: dw stops an empty Record with HANDOUT_EMPTY before the host starts. */
  pages: z.array(handoutPageSchema).min(1),
})
export type HandoutInput = z.infer<typeof handoutInputSchema>

/**
 * The data explain_build embeds in a built page (the `DW_DATA` line of page.html). `mode` is set
 * only for the Handout audience; a page without it renders exactly as the HUD's (eng D5, D6).
 */
export const pageDataSchema = z.object({
  n: z.number().int().positive(),
  title: z.string(),
  /** Section name; page.html shows it above the title. */
  step: z.string(),
  /** The source with audience markers already filtered for this audience (eng D2). */
  markdown: z.string(),
  mode: z.literal('handout').optional(),
})
export type PageData = z.infer<typeof pageDataSchema>

/** Scripts a Handout-mode page reports as loaded; one missing means HANDOUT_VENDOR (eng C9). */
export const pageLibrarySchema = z.enum(['marked', 'highlight', 'highlight-http', 'mermaid', 'purify'])
export type PageLibrary = z.infer<typeof pageLibrarySchema>

/**
 * What page.html posts on the `dw` message channel once it rendered. The HUD reads the same report;
 * Handout mode keeps it (eng C1) and adds `libs`. The host waits for the report whose `page` is the
 * page it loaded.
 */
export const renderReportSchema = z.object({
  type: z.literal('rendered'),
  page: z.number().int().positive(),
  /** Diagrams on the page, rendered or not. */
  diagrams: z.number().int().nonnegative(),
  /** One line per problem: a diagram that failed (`diagram 2: …`), a library that was missing. */
  errors: z.array(z.string()),
  /** Handout mode only: the libraries that loaded. */
  libs: z.array(pageLibrarySchema).optional(),
})
export type RenderReport = z.infer<typeof renderReportSchema>

/**
 * What the builder asks of the host, by `window.webkit.messageHandlers.host.postMessage(request)`,
 * which resolves with a {@link HostReply}. Only the builder view has this channel: author content in
 * the page view can never read a file (eng C2a).
 *
 * A `probe` is the body of an async function the host evaluates in the page view, after the page
 * reported (`render`) or loaded (`verify`); it returns a JSON value the builder parses itself. The
 * measuring and checking code stays in the builder, where it is tested.
 */
export const hostRequestSchema = z.discriminatedUnion('type', [
  /** Load `pages/NNN.html` of `explainDir` in the page view, wait for its report, run the probe. */
  z.object({ type: z.literal('render'), page: z.number().int().positive(), probe: z.string().min(1) }),
  /** Read a local file (an image, the page template, highlight.css). */
  z.object({ type: z.literal('read'), path: z.string().min(1) }),
  /** Open the finished Handout in the page view under its own CSP and run the probe (eng D10). */
  z.object({ type: z.literal('verify'), html: z.string().min(1), probe: z.string().min(1) }),
])
export type HostRequest = z.infer<typeof hostRequestSchema>

/**
 * The host's reply to a {@link HostRequest}. A time limit, an ended web content process or a
 * builder exception gets no reply: the host ends the run at once with HANDOUT_RENDERER (eng A4).
 */
export const hostReplySchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('rendered'), report: renderReportSchema, probe: z.unknown() }),
  /** The file's bytes, base64. */
  z.object({ type: z.literal('file'), base64: z.string() }),
  /** The file is missing or unreadable: the builder decides what that means (HANDOUT_IMAGE, HANDOUT_TEMPLATE). */
  z.object({ type: z.literal('unreadable'), message: z.string() }),
  z.object({ type: z.literal('verified'), probe: z.unknown() }),
])
export type HostReply = z.infer<typeof hostReplySchema>

/** What `window.dwHandout.build(input)` resolves with: the Handout to publish, or why there is none. */
export const buildOutcomeSchema = z.discriminatedUnion('ok', [
  z.object({
    ok: z.literal(true),
    /** The whole Handout, verified under its own CSP, starting with {@link HANDOUT_HEAD}. */
    html: z.string().min(1),
    pages: z.number().int().positive(),
    diagrams: z.number().int().nonnegative(),
    warnings: z.array(warningSchema),
  }),
  z.object({ ok: z.literal(false), diagnostics: z.array(diagnosticSchema).min(1) }),
])
export type BuildOutcome = z.infer<typeof buildOutcomeSchema>

/**
 * The host's result: one JSON line on its standard output, read by dw with jq. dw prints
 * `handout: written <path> (N pages, M diagrams, K warnings)` from a success, adding its own
 * warnings (HUD wording, a journal it could not write), or the diagnostics with exit 1.
 */
export const hostResultSchema = z.discriminatedUnion('ok', [
  z.object({
    v: z.literal(HANDOUT_PROTOCOL_VERSION),
    ok: z.literal(true),
    /** The published Handout. */
    path: z.string().min(1),
    pages: z.number().int().positive(),
    diagrams: z.number().int().nonnegative(),
    warnings: z.array(warningSchema),
  }),
  z.object({
    v: z.literal(HANDOUT_PROTOCOL_VERSION),
    ok: z.literal(false),
    diagnostics: z.array(diagnosticSchema).min(1),
    /** The host's log, for HANDOUT_RENDERER. */
    log: z.string().min(1),
  }),
])
export type HostResult = z.infer<typeof hostResultSchema>
