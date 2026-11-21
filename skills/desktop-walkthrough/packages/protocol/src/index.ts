/**
 * The protocol between the Bridge (the plugin's hooks module, inside a Claude Code Session) and the
 * HUD: what the Bridge tells the HUD about the Session so that the Mirror can draw it.
 *
 * Why it exists: the Bridge runs in Claude Code's plugin sandbox, the HUD is a Swift app and the
 * Mirror's drawing is a web page inside it. They meet only in JSON files, so the shape of that JSON
 * is written once, here: the Bridge imports the types, the Mirror checks what it receives against
 * the schemas, and the tests of both use the same sample data.
 */
import { z } from 'zod'

/** Version of the document the Bridge writes; the Mirror refuses a document it does not know. */
export const PROTOCOL_VERSION = 1

/** What a running turn is doing, as Claude Code's spinner tells it. */
export const spinnerModeSchema = z.enum(['requesting', 'responding', 'thinking', 'tool-input', 'tool-use'])
export type SpinnerMode = z.infer<typeof spinnerModeSchema>

/** A Prompt as its Row shows it: the user's own, or one that came from elsewhere. */
export const promptRowSchema = z.object({
  kind: z.literal('prompt'),
  id: z.string(),
  text: z.string(),
  /** Who sent it: the person at the terminal, the HUD's Input box, a background task, another agent. */
  origin: z.enum(['user', 'hud', 'notification', 'peer', 'other']),
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
  isSummary: z.literal(true).optional(),
})
export type ReplyRow = z.infer<typeof replyRowSchema>

/** A tool call and, once it resolved, its result. */
export const toolRowSchema = z.object({
  kind: z.literal('tool'),
  id: z.string(),
  /** The tool's name as the Session calls it (`Bash`, `Read`, `mcp__server__tool`). */
  tool: z.string(),
  /** The call's input as the model sent it. */
  input: z.unknown(),
  state: z.enum(['running', 'done', 'errored', 'interrupted']),
  /** The tool's result, cut down by the Bridge to what a Row shows. */
  output: z.unknown().optional(),
})
export type ToolRow = z.infer<typeof toolRowSchema>

/** The line that closes a turn (`Baked for 3s`). */
export const turnDurationRowSchema = z.object({
  kind: z.literal('turn-duration'),
  id: z.string(),
  word: z.string(),
  durationMs: z.number(),
})
export type TurnDurationRow = z.infer<typeof turnDurationRowSchema>

/** One Row of the Transcript. */
export const rowSchema = z.discriminatedUnion('kind', [
  promptRowSchema,
  replyRowSchema,
  toolRowSchema,
  turnDurationRowSchema,
])
export type Row = z.infer<typeof rowSchema>

/** What changes while a turn runs: the Spinner line's inputs and the footer under the Input box. */
export const liveSchema = z.object({
  /** True while a turn of the Session runs. */
  isBusy: z.boolean(),
  /** When the running turn began, in milliseconds since 1970. */
  startedAt: z.number().optional(),
  spinner: z
    .object({
      /** The word the terminal's spinner shows (`Puzzling`). */
      word: z.string(),
      /** What follows the word (`…`). */
      suffix: z.string(),
      mode: spinnerModeSchema,
    })
    .optional(),
  /** The hint line under the Input box, as the terminal words it. */
  hint: z.string().optional(),
})
export type Live = z.infer<typeof liveSchema>

/** Everything the Mirror draws, as the Bridge last wrote it. */
export const mirrorDocumentSchema = z.object({
  v: z.literal(PROTOCOL_VERSION),
  sessionId: z.string(),
  /** The Transcript, oldest Row first. */
  rows: z.array(rowSchema),
  live: liveSchema,
})
export type MirrorDocument = z.infer<typeof mirrorDocumentSchema>
