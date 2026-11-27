/**
 * The builder's entry: one Record's pages in, one verified Handout (or the reasons there is none) out.
 *
 * Flow (eng review, final diagram; the host renders, reads and reopens on request):
 *
 * ```
 * scan sources, titles, sections ───────────────▶ HANDOUT_SECRET   (before anything renders)
 * read page.html, cut the reading marks ────────▶ HANDOUT_TEMPLATE
 * read vendor/highlight.css ────────────────────▶ HANDOUT_VENDOR
 * per page: host renders pages/NNN.html, probe measures with every <details> open
 *   libraries missing ──────────────────────────▶ HANDOUT_VENDOR   (once per run)
 *   diagram failed / nothing laid out ──────────▶ HANDOUT_DIAGRAM
 *   label larger than its box ──────────────────▶ HANDOUT_OVERFLOW
 * embed local images ───────────────────────────▶ HANDOUT_IMAGE
 * sanitize, assemble (CSS, controller, CSP, marker)
 * host reopens the file under its CSP: labels equal, controller runs ─▶ HANDOUT_VERIFY
 * ```
 *
 * Each stage reports every problem it found, then the export stops: the agent fixes them in one pass.
 */
import type { BuildOutcome, Diagnostic, HandoutInput } from '../contract'
import { VERIFY_HASHCHANGE_LIMIT_MS, VERIFY_POLL_MS, VERIFY_READY_LIMIT_MS } from '../constants'
import { HANDOUT_DOM } from '../dom'
import { decodeBase64 } from '../utils/decodeBase64'
import { assembleHandout } from './assemble'
import type { HostPort } from './host'
import { readFile, renderPage, verifyInHost } from './host'
import { embedImages } from './images'
import { judgeRenderedPage, missingLibraries } from './judge'
import { checkHandout, handoutCheckSchema, measurePage, pageMeasurementSchema, probeBody } from './probes'
import { sanitizePage } from './sanitize'
import { scanForSecrets } from './scan'
import { handoutCss } from './template'
import type { DiagramLabels } from './verify'
import { judgeVerification } from './verify'

/** Id of the element page.html renders a page's content into. */
const PAGE_CONTENT_ID = 'content'

/** A stopped export: the reasons the first failing stage found. */
const fail = (diagnostics: Diagnostic[]): BuildOutcome => ({ ok: false, diagnostics })

/** What the builder needs besides the input: the host, and the parts built with it. */
export interface BuildDependencies {
  host: HostPort
  /** The Handout's own CSS (controller/handout.css). */
  handoutCss: string
  /** The controller's built source and its base64 SHA-256 (dist/controller.js). */
  controller: { source: string; sha256: string }
}

/**
 * Build one Handout from a Record's pages, checking everything the colleague will see on the way.
 *
 * Why it exists: `dw handout` must be self-verifying (DX D6): when it says "written", the file is
 * complete, safe to share and works as one file. Called by the builder page's `dwHandout.build`,
 * which the renderer host invokes with input.json.
 *
 * @param input - input.json as dw wrote it, already parsed.
 * @param dependencies - The host and the controller.
 * @returns
 * - `{ ok: true, html, pages, diagrams, warnings }`: the Handout to publish
 * - `{ ok: false, diagnostics }`: every problem of the first stage that found any
 * @throws When the host breaks the contract or a probe returns something unexpected: the host
 * reports that as HANDOUT_RENDERER, since no page content can cause it.
 *
 * @example
 * await buildHandout(input, { host: webkitHost, handoutCss, controller }) // { ok: true, html: '<!doctype html>…', pages: 12, diagrams: 7, warnings: [] }
 */
export async function buildHandout(
  input: HandoutInput,
  dependencies: BuildDependencies,
): Promise<BuildOutcome> {
  const { host } = dependencies

  const secrets = scanForSecrets(input.pages)
  if (secrets.length > 0) return fail(secrets)

  const template = await readFile(host, input.template)
  if (!template.ok) {
    return fail([
      { code: 'HANDOUT_TEMPLATE', message: `explainer/page.html could not be read: ${template.message}` },
    ])
  }
  const pageCss = handoutCss(new TextDecoder().decode(decodeBase64(template.base64)))
  if (!pageCss.ok)
    return fail([{ code: 'HANDOUT_TEMPLATE', message: `explainer/page.html: ${pageCss.reason}` }])
  const highlight = await readFile(host, `${input.explainDir}/vendor/highlight.css`)
  if (!highlight.ok) {
    return fail([
      { code: 'HANDOUT_VENDOR', message: 'highlight.css is missing from the vendor folder: run dw doctor' },
    ])
  }

  const diagnostics: Diagnostic[] = []
  const rendered: Array<{ page: HandoutInput['pages'][number]; html: string }> = []
  const expectedLabels: DiagramLabels[] = []
  let diagramCount = 0
  let vendorReported = false
  const measureProbe = probeBody(measurePage, { contentId: PAGE_CONTENT_ID })
  for (const page of input.pages) {
    const { report, probe } = await renderPage(host, page.n, measureProbe)
    const measurement = pageMeasurementSchema.parse(probe)
    diagramCount += report.diagrams
    const missing = missingLibraries(report)
    // One missing library breaks every page alike: say it once
    if (missing.length > 0 && !vendorReported) {
      vendorReported = true
      diagnostics.push({
        code: 'HANDOUT_VENDOR',
        message: `page ${page.n} rendered without ${missing.join(', ')}: the explainer libraries did not load (run dw doctor)`,
        page: page.n,
      })
    }
    diagnostics.push(...judgeRenderedPage(page, report, measurement))
    for (const diagram of measurement.diagrams) {
      expectedLabels.push({
        id: diagram.id,
        labels: diagram.labels.map((label) => label.text).filter((text) => text !== ''),
      })
    }
    rendered.push({ page, html: measurement.html })
  }
  if (diagnostics.length > 0) return fail(diagnostics)

  const embedded: Array<{ page: HandoutInput['pages'][number]; html: string }> = []
  for (const { page, html } of rendered) {
    const result = await embedImages(page, html, input.record.dir, host)
    diagnostics.push(...result.diagnostics)
    embedded.push({ page, html: result.html })
  }
  if (diagnostics.length > 0) return fail(diagnostics)

  const pages = embedded.map(({ page, html }) => ({
    n: page.n,
    title: page.title,
    section: page.section,
    html: sanitizePage(html),
  }))
  const html = assembleHandout({
    pages,
    pageCss: pageCss.css,
    highlightCss: new TextDecoder().decode(decodeBase64(highlight.base64)),
    handoutCss: dependencies.handoutCss,
    controller: dependencies.controller,
  })

  const checkProbe = probeBody(checkHandout, {
    readyAttribute: HANDOUT_DOM.readyAttribute,
    pageClass: HANDOUT_DOM.pageClass,
    pageIdPrefix: HANDOUT_DOM.pageIdPrefix,
    pageNumberId: HANDOUT_DOM.pageNumberId,
    readyLimitMs: VERIFY_READY_LIMIT_MS,
    pollMs: VERIFY_POLL_MS,
    hashChangeLimitMs: VERIFY_HASHCHANGE_LIMIT_MS,
  })
  const check = handoutCheckSchema.parse(await verifyInHost(host, html, checkProbe))
  const verification = judgeVerification(expectedLabels, check, pages.length)
  if (verification.length > 0) return fail(verification)

  return { ok: true, html, pages: pages.length, diagrams: diagramCount, warnings: [] }
}
