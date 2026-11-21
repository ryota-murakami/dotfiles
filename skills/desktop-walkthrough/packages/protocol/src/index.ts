/**
 * The protocol between the Bridge (the plugin's hooks module, inside a Claude Code Session), the HUD
 * and the Mirror's page: what the Bridge tells about the Session so that the Mirror can draw it, and
 * what the page tells the HUD back.
 *
 * Why it exists: the Bridge runs in Claude Code's plugin sandbox, the HUD is a Swift app and the
 * Mirror's drawing is a web page inside it. They meet only in JSON, so the shape of that JSON is
 * written once, here: the Bridge imports the types, the page checks what it receives against the
 * schemas, and the tests of both use the same sample data.
 *
 * A Row carries what Claude Code hands its own terminal UI for that row (the props of its row
 * components), cut down by the Bridge to what a Row shows. How a Row is drawn is not in here.
 */
import { z } from 'zod'

/** Version of the documents the Bridge writes; the page refuses a document it does not know. */
export const PROTOCOL_VERSION = 1

/**
 * A long text cut down by the Bridge: its head, and how long the whole was.
 *
 * Why it exists: a Row shows the first lines of a command's output and how many more there were;
 * the megabytes behind them have no business in the HUD.
 */
export const clippedSchema = z.object({
  /** The first lines of the text. */
  head: z.string(),
  /** Lines of the whole text. */
  lines: z.number(),
  /** Characters of the whole text. */
  chars: z.number(),
})
export type Clipped = z.infer<typeof clippedSchema>

/** A text as the Bridge passes it on: whole when short, clipped when long. */
export type Text = string | Clipped

/** What a running turn is doing, as Claude Code's spinner tells it. */
export const spinnerModeSchema = z.enum(['requesting', 'responding', 'thinking', 'tool-input', 'tool-use'])
export type SpinnerMode = z.infer<typeof spinnerModeSchema>

/** A Prompt's Row: the user's own words, or a message that reached the Session another way. */
export const promptRowSchema = z.object({
  kind: z.literal('prompt'),
  id: z.string(),
  /** What the row shows: the prompt as typed, a notification's summary, another party's message. */
  text: z.string(),
  /** Where it came from, as Claude Code names it (`composer`, `plugin`, `task-notification`, `peer`, …). */
  origin: z.string(),
  /**
   * The sender's name: the agent or session of a `peer` message, the plugin of a `plugin` prompt
   * (the HUD's own prompts name the skill), shown on the dim line above the prompt.
   */
  from: z.string().optional(),
  /** How a background task ended, for a `task-notification`: it colours the row's bullet. */
  status: z.enum(['completed', 'failed', 'killed']).optional(),
  /** How long the background task of a `task-notification` ran, in milliseconds: shown dim after ` · `. */
  durationMs: z.number().optional(),
})
export type PromptRow = z.infer<typeof promptRowSchema>

/** One block of the agent's reply, markdown. */
export const replyRowSchema = z.object({
  kind: z.literal('reply'),
  id: z.string(),
  text: z.string(),
  /** True on the block that opens a reply: it draws the reply's bullet. */
  isFirstOfReply: z.boolean(),
  /** True on a block that summarizes text the model wrote between two tool calls. */
  isSummary: z.boolean().optional(),
})
export type ReplyRow = z.infer<typeof replyRowSchema>

/** A tool call with, once it resolved, its result. */
export const toolCallSchema = z.object({
  /** The tool's name as the Session calls it (`Bash`, `Read`, `mcp__server__tool`). */
  tool: z.string(),
  /**
   * The call's input as the model sent it, cut down by the Bridge: a long text inside it is a
   * {@link Clipped} (its head and the size of the whole), and a long list ends with
   * `{ __dwMore: n }`, n being the items left out.
   */
  input: z.unknown(),
  isRunning: z.boolean(),
  isErrored: z.boolean(),
  isInterrupted: z.boolean(),
  /** The tool's own result object once the call resolved, cut down the same way as `input`. */
  output: z.unknown().optional(),
  /**
   * How long the terminal showed the call running, in milliseconds, once it has resolved. A shell
   * command that ran for seconds keeps a note of its timeout under its output.
   */
  ranMs: z.number().optional(),
})
export type ToolCall = z.infer<typeof toolCallSchema>

export const toolRowSchema = toolCallSchema.extend({
  kind: z.literal('tool'),
  id: z.string(),
})
export type ToolRow = z.infer<typeof toolRowSchema>

/** A run of tool calls the terminal folds into one line (`Read 3 files, ran 2 shell commands`). */
export const toolGroupRowSchema = z.object({
  kind: z.literal('tool-group'),
  id: z.string(),
  /** In the order the model made them. */
  calls: z.array(toolCallSchema),
  /** True while a call in the group may still run and the next call may join it. */
  isActive: z.boolean(),
  /**
   * How long the model thought inside the run, in milliseconds: the line's `Thought for 8s`. Absent
   * when it did not think there, and for a run drawn before the Bridge was watching.
   */
  thoughtMs: z.number().optional(),
})
export type ToolGroupRow = z.infer<typeof toolGroupRowSchema>

/** What a slash command printed under its echo. */
export const commandOutputRowSchema = z.object({
  kind: z.literal('command-output'),
  id: z.string(),
  /** The command, without its slash. */
  command: z.string(),
  args: z.string(),
  /** What it printed, markdown. */
  text: z.string(),
  isErrored: z.boolean(),
})
export type CommandOutputRow = z.infer<typeof commandOutputRowSchema>

/** The line that closes a turn (`Baked for 3s`). */
export const turnDurationRowSchema = z.object({
  kind: z.literal('turn-duration'),
  id: z.string(),
  /** The past-tense word the line drew (`Baked`). */
  word: z.string(),
  durationMs: z.number(),
  /** When the turn finished, in milliseconds since 1970: the line adds ` · done 3:04 PM` after it. */
  finishedAt: z.number().optional(),
  /**
   * What still ran in the background when the turn closed, as the terminal counts it (`3 shells`):
   * the line ends with ` · 3 shells still running`.
   */
  stillRunning: z.string().optional(),
})
export type TurnDurationRow = z.infer<typeof turnDurationRowSchema>

/** A dim notice (the model's source, a settings hint), with a slash command after it when it has one. */
export const noticeRowSchema = z.object({
  kind: z.literal('notice'),
  id: z.string(),
  text: z.string(),
  command: z.string().nullable(),
})
export type NoticeRow = z.infer<typeof noticeRowSchema>

/** A line a plugin wrote into the transcript, shown dim as `<plugin>: <text>`. */
export const logRowSchema = z.object({
  kind: z.literal('log'),
  id: z.string(),
  /** The plugin that wrote the line, as the terminal names it before the text. */
  plugin: z.string(),
  text: z.string(),
})
export type LogRow = z.infer<typeof logRowSchema>

/** One Row of the Transcript. */
export const rowSchema = z.discriminatedUnion('kind', [
  promptRowSchema,
  replyRowSchema,
  toolRowSchema,
  toolGroupRowSchema,
  commandOutputRowSchema,
  turnDurationRowSchema,
  noticeRowSchema,
  logRowSchema,
])
export type Row = z.infer<typeof rowSchema>

/** The Transcript as the Bridge last wrote it. */
export const transcriptDocumentSchema = z.object({
  v: z.literal(PROTOCOL_VERSION),
  sessionId: z.string(),
  /** Rows the Bridge dropped from the start to keep the document small. */
  dropped: z.number(),
  /** Oldest Row first. */
  rows: z.array(rowSchema),
})
export type TranscriptDocument = z.infer<typeof transcriptDocumentSchema>

/**
 * The Transcript with its Rows left unchecked.
 *
 * Why it exists: a new Transcript arrives several times a second and differs from the one before in
 * a Row or two; a reader that checks only the Rows that changed starts from this.
 */
export const transcriptEnvelopeSchema = transcriptDocumentSchema.extend({ rows: z.array(z.unknown()) })

/** What changes while a turn runs: what the Spinner line and the footer under the Input box are drawn from. */
export const liveDocumentSchema = z.object({
  v: z.literal(PROTOCOL_VERSION),
  /** True while a turn of the Session runs. */
  isBusy: z.boolean(),
  /** When the running turn began, in milliseconds since 1970. */
  startedAt: z.number().optional(),
  spinner: z
    .object({
      /** The word the terminal's spinner shows (`Puzzling`), or the text that overrides it. */
      word: z.string(),
      /** What follows the word (`…`). */
      suffix: z.string(),
      mode: spinnerModeSchema,
    })
    .optional(),
  /**
   * How much the model has written in the running turn, in characters, as Claude Code's spinner
   * counts it: four per output token of each finished response, plus the characters of the response
   * that is arriving. The Spinner line shows a quarter of it as tokens.
   */
  responseLength: z.number().optional(),
  /** Effort of the turn's requests (`xhigh`), as "thinking with … effort" names it. */
  effort: z.string().optional(),
  /**
   * The Session's permission mode as Claude Code names it (`default`, `acceptEdits`, `plan`,
   * `bypassPermissions`, `dontAsk`, `auto`): the pill that opens the hint line. Absent until the
   * Bridge has heard it.
   */
  permissionMode: z.string().optional(),
  /** The hint line under the Input box, as the terminal words it (the permission pill is not in it). */
  hint: z.string().optional(),
  /** The mode labels at the right of the footer (`focus`, `memory paused`), which the terminal joins with ` & `. */
  modes: z.array(z.string()).optional(),
})
export type LiveDocument = z.infer<typeof liveDocumentSchema>

/** What the page tells the HUD. */
export const pageMessageSchema = z.discriminatedUnion('type', [
  /** The page has loaded and takes documents. */
  z.object({ type: z.literal('ready') }),
  /** The user sent a Prompt from the Input box. */
  z.object({ type: z.literal('submit'), text: z.string() }),
  /** The user asked to stop the running turn (Esc on an empty Input box while a turn runs). */
  z.object({ type: z.literal('interrupt') }),
  /** The user is done with the Input box: the keyboard goes back to the app they came from (Esc on an empty Input box while nothing runs). */
  z.object({ type: z.literal('release') }),
  /** The Input box took or lost the keyboard. */
  z.object({ type: z.literal('focus'), isFocused: z.boolean() }),
  /** The Input box holds a draft, or no longer does: while it does, the agent's GUI steps wait. */
  z.object({ type: z.literal('draft'), hasDraft: z.boolean() }),
])
export type PageMessage = z.infer<typeof pageMessageSchema>
