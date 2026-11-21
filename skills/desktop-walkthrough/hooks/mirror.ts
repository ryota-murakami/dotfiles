import type { EngineInterface, Register, RenderPropsOf, TurnStepChunk } from 'claude-code'

import type { LiveDocument, Row, Text, ToolCall, TranscriptDocument } from '../packages/protocol/src/index'
import { maskSecrets } from './secrets'

/**
 * What the Bridge writes for the Mirror: the Session's conversation as Rows, and the live state the
 * Spinner line and the footer are drawn from (the documents of `packages/protocol`).
 *
 * How it knows what to write: Claude Code raises a drawing event for every row of its terminal UI
 * and hands the row's own data with it (a prompt's text, a tool call's input and result, the
 * spinner's word and mode). The hooks here only watch those events (every drawing passes on
 * untouched), keep the newest data of each row in the order the terminal shows them, and write it
 * out a few times a second while a HUD of this Session is running.
 *
 * Files, in the state folder's `bridge/`:
 * - `mirror-transcript.json`  mod → HUD  the Transcript (TranscriptDocument)
 * - `mirror-live.json`        mod → HUD  what changes while a turn runs (LiveDocument)
 */

type On = Parameters<Register>[0]

/** Rows kept; older ones are dropped from the start and counted. */
export const ROW_LIMIT = 400
/** A long text inside a tool's input or result keeps this much: more than any Row shows. */
const HEAD_LINES = 40
const HEAD_CHARS = 6000
/** A prompt's or a reply's text keeps this much. */
const TEXT_CHARS = 60_000
/** A list inside a tool's input or result keeps this many items. */
const LIST_ITEMS = 200
/** Drawings closer together than this belong to one pass of the terminal over its rows. */
const PASS_GAP_MS = 80
/** A pass that drew at least this many rows is a redraw of rows in their order, not one row changing. */
const REDRAW_ROWS = 3
/** How far back a prompt looks for an earlier drawing of itself. */
const SAME_PROMPT_REACH = 60

/**
 * Cut a long text down to its head and say how long the whole was; hide secrets in what is kept.
 *
 * Why it exists: a tool's result can be megabytes, and a Row shows its first lines and a count of
 * the rest. Called by {@link clipValue} for every text of a tool's input and result.
 *
 * @param text - The text as the tool has it.
 * @param maxLines - Lines to keep.
 * @param maxChars - Characters to keep.
 * @returns The text itself when it is short, else its head with the whole text's line and character counts.
 *
 * @example
 * clipText('a\nb\nc', 2, 100) // { head: 'a\nb', lines: 3, chars: 5 }
 */
export function clipText(text: string, maxLines = HEAD_LINES, maxChars = HEAD_CHARS): Text {
  let lines = 1
  let cut = -1
  // Count the lines without splitting the text: it may be megabytes
  for (let at = text.indexOf('\n'); at !== -1; at = text.indexOf('\n', at + 1)) {
    if (lines === maxLines && cut === -1) cut = at
    lines += 1
  }
  if (cut === -1 && text.length <= maxChars) return maskSecrets(text)
  const end = Math.min(cut === -1 ? text.length : cut, maxChars)
  // Masked with some text past the cut, so a secret that straddles it is still recognized whole
  return { head: maskSecrets(text.slice(0, end + 256)).slice(0, end), lines, chars: text.length }
}

/**
 * A tool's input or result as a Row carries it: every long text clipped, every long list cut, with
 * `{ __dwMore: n }` as the last item of a cut list (n items were left out).
 *
 * Called by {@link buildRow} for the `input` and `output` of tool calls.
 *
 * @param value - The value as Claude Code hands it to its own row.
 * @returns A copy that is safe and small enough for the HUD.
 */
export function clipValue(value: unknown, depth = 0): unknown {
  if (typeof value === 'string') return clipText(value)
  if (value === null || typeof value !== 'object') return value
  // Deeper than any tool's result goes: left out rather than walked forever
  if (depth >= 8) return undefined
  if (Array.isArray(value)) {
    const kept: unknown[] = value.slice(0, LIST_ITEMS).map(item => clipValue(item, depth + 1))
    if (value.length > LIST_ITEMS) kept.push({ __dwMore: value.length - LIST_ITEMS })
    return kept
  }
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clipValue(item, depth + 1)]))
}

/** Where the rows stand, and what the terminal's current pass over them has drawn so far. */
export type Placement = {
  /** Row ids, oldest row first. */
  order: string[]
  /** When the last row was drawn, and which. */
  lastAt: number
  lastId: string | undefined
  /** Rows the current pass has drawn. */
  passCount: number
  /** Rows new to us that the current pass drew before any row we already held. */
  leading: string[]
}

/** An empty {@link Placement}. */
export function newPlacement(): Placement {
  return { order: [], lastAt: 0, lastId: undefined, passCount: 0, leading: [] }
}

/**
 * Give a row that was just drawn its place among the rows.
 *
 * Why it exists: a drawing event says which row was drawn, not where it stands. Usually a new row
 * is the newest and goes last. But the terminal also redraws many rows at once, top to bottom
 * (after a resize, when the plugin loads), and such a pass can hold rows we have not seen that
 * stand between or before rows we have: those take the place the pass shows. Called by
 * {@link capture} for every row drawn.
 *
 * @param placement - Where the rows stand; changed in place.
 * @param id - The row that was drawn.
 * @param now - When, in milliseconds.
 */
export function place(placement: Placement, id: string, now: number) {
  const inPass = now - placement.lastAt <= PASS_GAP_MS
  if (!inPass) {
    placement.passCount = 0
    placement.leading = []
  }
  const at = placement.order.indexOf(id)
  if (at !== -1) {
    // A row we hold: new rows this pass drew before it stand before it, not at the end
    const first = placement.leading[0]
    if (first !== undefined && placement.order.indexOf(first) > at) {
      const moved = new Set(placement.leading)
      placement.order = placement.order.filter(row => !moved.has(row))
      placement.order.splice(placement.order.indexOf(id), 0, ...placement.leading)
    }
    placement.leading = []
  } else {
    const anchor = inPass && placement.lastId !== undefined ? placement.order.indexOf(placement.lastId) : -1
    if (anchor !== -1 && placement.passCount >= REDRAW_ROWS - 1) {
      // In a redraw: right after the row the pass drew just before it
      placement.order.splice(anchor + 1, 0, id)
      if (placement.lastId !== undefined && placement.leading.includes(placement.lastId)) placement.leading.push(id)
    } else {
      placement.order.push(id)
      // Still before any row we held: if such a row follows in this pass, these go before it
      if (placement.passCount === placement.leading.length) placement.leading.push(id)
    }
  }
  placement.passCount += 1
  placement.lastAt = now
  placement.lastId = id
}

/** A row as the terminal last drew it: which of its components, and the data it was handed. */
type Captured =
  | { component: 'UserMessage'; props: RenderPropsOf['UserMessage'] }
  | { component: 'AssistantMessage'; props: RenderPropsOf['AssistantMessage'] }
  | { component: 'ToolUse'; props: RenderPropsOf['ToolUse']; result?: RenderPropsOf['ToolResult'] }
  | { component: 'ToolGroup'; props: RenderPropsOf['ToolGroup'] }
  | { component: 'CommandOutput'; props: RenderPropsOf['CommandOutput'] }
  | { component: 'TurnDuration'; props: RenderPropsOf['TurnDuration']; finishedAt?: number }
  | { component: 'InfoNotice'; props: RenderPropsOf['InfoNotice'] }

/** The Bridge's memory of the Mirror; module variables start over on every reload. */
const M = {
  captured: new Map<string, Captured>(),
  placement: newPlacement(),
  dropped: 0,
  /** Rows whose data changed since they were last built into a Row. */
  stale: new Set<string>(),
  built: new Map<string, Row>(),
  transcriptChanged: false,
  transcriptWritten: false,
  live: { v: 1, isBusy: false } as LiveDocument,
  liveWritten: '',
  /** The running turn of the main loop: its id, the length of its finished responses, and of the one arriving. */
  turn: undefined as string | undefined,
  finishedLength: 0,
  arrivingLength: 0,
  /** When the last turn ended: a turn-duration row drawn right after it ended then. */
  turnEndedAt: 0,
  flushing: false,
}

/** Text of a prompt or reply as a Row carries it: secrets hidden, an extreme length cut. */
function rowText(text: string): string {
  const masked = maskSecrets(text)
  return masked.length > TEXT_CHARS ? `${masked.slice(0, TEXT_CHARS)}…` : masked
}

/** A tool call as a Row carries it. */
function toolCall(call: {
  tool: string
  input: unknown
  isRunning: boolean
  isErrored: boolean
  isInterrupted: boolean
  output?: unknown
}): ToolCall {
  return {
    tool: call.tool,
    input: clipValue(call.input),
    isRunning: call.isRunning,
    isErrored: call.isErrored,
    isInterrupted: call.isInterrupted,
    ...(call.output === undefined ? {} : { output: clipValue(call.output) }),
  }
}

/** How a background task ended, in the words the protocol has for it. */
function taskStatus(status: string | undefined): 'completed' | 'failed' | 'killed' | undefined {
  return status === 'completed' || status === 'failed' || status === 'killed' ? status : undefined
}

/**
 * Build the Row the Mirror draws from what the terminal handed its own row.
 *
 * Called by {@link flushMirror} for every row whose data changed since the last write.
 *
 * @param id - The row's id.
 * @param captured - The component and its data.
 * @returns The Row, or undefined for a row that draws nothing (a folded run with no calls).
 */
export function buildRow(id: string, captured: Captured): Row | undefined {
  switch (captured.component) {
    case 'UserMessage': {
      const { text, origin, from, task } = captured.props
      const sender = from?.name ?? ('name' in origin && typeof origin.name === 'string' ? origin.name : undefined)
      const status = taskStatus(task?.status)
      return {
        kind: 'prompt',
        id,
        text: rowText(text),
        origin: origin.kind,
        ...(sender === undefined ? {} : { from: sender }),
        ...(status === undefined ? {} : { status }),
        ...(task?.durationMs === undefined ? {} : { durationMs: task.durationMs }),
      }
    }
    case 'AssistantMessage': {
      const { text, isFirstOfReply, isSummary } = captured.props
      return { kind: 'reply', id, text: rowText(text), isFirstOfReply, ...(isSummary ? { isSummary: true } : {}) }
    }
    case 'ToolUse': {
      const { props, result } = captured
      return {
        kind: 'tool',
        id,
        ...toolCall({
          ...props,
          isErrored: props.isErrored || (result?.isErrored ?? false),
          output: props.output ?? result?.output,
        }),
      }
    }
    case 'ToolGroup': {
      // A run with no calls draws nothing in the terminal either
      if (captured.props.calls.length === 0) return undefined
      return { kind: 'tool-group', id, calls: captured.props.calls.map(toolCall), isActive: captured.props.isActive }
    }
    case 'CommandOutput': {
      const { command, args, text, isErrored } = captured.props
      return { kind: 'command-output', id, command, args: maskSecrets(args), text: rowText(text), isErrored }
    }
    case 'TurnDuration': {
      const { word, durationMs } = captured.props
      return {
        kind: 'turn-duration',
        id,
        word,
        durationMs,
        ...(captured.finishedAt === undefined ? {} : { finishedAt: captured.finishedAt }),
      }
    }
    case 'InfoNotice':
      return { kind: 'notice', id, text: maskSecrets(captured.props.text), command: captured.props.command }
  }
}

/** Forget a row. */
function drop(id: string) {
  M.captured.delete(id)
  M.built.delete(id)
  M.stale.delete(id)
  M.placement.order = M.placement.order.filter(row => row !== id)
}

/**
 * A prompt that is drawn again under a new id takes the place of its earlier drawing.
 *
 * Why it exists: a prompt typed while the agent works is drawn where the queue shows it, and again,
 * under another id, once it is delivered; kept twice, the Mirror would show it twice. Called by
 * {@link capture} for a prompt it has not seen. It looks back only within the current turn.
 */
function dropEarlierDrawing(props: RenderPropsOf['UserMessage']) {
  const order = M.placement.order
  for (let at = order.length - 1; at >= 0 && at >= order.length - SAME_PROMPT_REACH; at--) {
    const id = order[at]
    const earlier = id === undefined ? undefined : M.captured.get(id)
    if (id === undefined || earlier === undefined) continue
    // The line that closed the turn before: the same words above it are another prompt
    if (earlier.component === 'TurnDuration') return
    if (earlier.component === 'UserMessage' && earlier.props.text === props.text && earlier.props.origin.kind === props.origin.kind) {
      drop(id)
      return
    }
  }
}

/**
 * Keep what the terminal just drew for one row.
 *
 * Called by every drawing hook of {@link registerMirror}. It only stores references: cutting and
 * masking wait for {@link flushMirror}, so a Session without a HUD pays next to nothing.
 */
function capture(id: string, captured: Captured) {
  const now = Date.now()
  const known = M.captured.get(id)
  if (known === undefined && captured.component === 'UserMessage') dropEarlierDrawing(captured.props)
  if (captured.component === 'TurnDuration') {
    // Drawn right after a turn ended: that is when it finished. On a later redraw the time stays
    const finishedAt = known?.component === 'TurnDuration' ? known.finishedAt : now - M.turnEndedAt < 3000 ? M.turnEndedAt : undefined
    if (finishedAt !== undefined) captured.finishedAt = finishedAt
  }
  // A tool row's result block is drawn apart from the row: a redraw of the row keeps it
  if (captured.component === 'ToolUse' && known?.component === 'ToolUse' && known.result && !captured.result) captured.result = known.result
  M.captured.set(id, captured)
  place(M.placement, id, now)
  M.stale.add(id)
  M.transcriptChanged = true
  // Past the limit the oldest rows go, and are counted
  while (M.placement.order.length > ROW_LIMIT) {
    const oldest = M.placement.order[0]
    if (oldest === undefined) break
    drop(oldest)
    M.dropped += 1
  }
}

/** Change the live state and remember that it has to be written. */
function setLive(change: Partial<LiveDocument>) {
  M.live = { ...M.live, ...change }
}

/**
 * Length of the text one piece of a streaming response adds: visible text, thinking, or a tool
 * call's arguments. The engine's own items (block starts and ends, the stop) add none.
 *
 * Why it exists: Claude Code's spinner shows "↓ N tokens" as a quarter of a length it keeps for the
 * turn: four per output token of each finished response, plus the characters of the response that is
 * arriving. The Mirror's line shows the same figure. Called by the `turn.step` hook for every chunk.
 *
 * @param chunk - One chunk of a `turn.step` stream.
 * @returns The number of characters it carries.
 *
 * @example
 * chunkChars({ kind: 'text', index: 0, text: 'done' }) // 4
 */
export function chunkChars(chunk: Pick<TurnStepChunk, 'kind'> & { text?: string; json?: string }): number {
  if (chunk.kind === 'text' || chunk.kind === 'thinking') return chunk.text?.length ?? 0
  if (chunk.kind === 'input') return chunk.json?.length ?? 0
  return 0
}

/** A turn of the main loop began. Called by the Bridge's `turn.start` hook. */
export function noteTurnStart(turnId: string) {
  M.turn = turnId
  M.finishedLength = 0
  M.arrivingLength = 0
  // The spinner of the turn before is not this turn's
  const { spinner: _spinner, effort: _effort, ...rest } = M.live
  M.live = { ...rest, isBusy: true, startedAt: Date.now(), responseLength: 0 }
}

/** The turn of the main loop ended. Called by the Bridge's `turn.complete` hook. */
export function noteTurnComplete() {
  M.turn = undefined
  M.turnEndedAt = Date.now()
  const { spinner: _spinner, startedAt: _startedAt, responseLength: _length, effort: _effort, ...rest } = M.live
  M.live = { ...rest, isBusy: false }
}

/**
 * Write the Transcript and the live state for the HUD, each only when it changed.
 *
 * Called by the Bridge a few times a second while a HUD of this Session runs, and once with
 * `force` when the Session takes a HUD over (the files may be another Session's).
 *
 * @param bridgeDir - The state folder's `bridge/`.
 * @param sessionId - This Session's id.
 * @param force - Write both documents even if nothing changed.
 */
export async function flushMirror($: EngineInterface, bridgeDir: string, sessionId: string, force = false) {
  // A slow write must not overlap the next one
  if (M.flushing) return
  M.flushing = true
  try {
    if (M.transcriptChanged || force || !M.transcriptWritten) {
      M.transcriptChanged = false
      for (const id of M.stale) {
        const captured = M.captured.get(id)
        const row = captured === undefined ? undefined : buildRow(id, captured)
        if (row === undefined) M.built.delete(id)
        else M.built.set(id, row)
      }
      M.stale.clear()
      const rows = M.placement.order.flatMap(id => {
        const row = M.built.get(id)
        return row === undefined ? [] : [row]
      })
      const transcript: TranscriptDocument = { v: 1, sessionId, dropped: M.dropped, rows }
      await $.fs.write(`${bridgeDir}/mirror-transcript.json`, JSON.stringify(transcript))
      M.transcriptWritten = true
    }
    const live = JSON.stringify({ ...M.live, ...(M.turn === undefined ? {} : { responseLength: M.finishedLength + M.arrivingLength }) })
    if (live !== M.liveWritten || force) {
      M.liveWritten = live
      await $.fs.write(`${bridgeDir}/mirror-live.json`, live)
    }
  } finally {
    M.flushing = false
  }
}

/**
 * Watch what the terminal draws.
 *
 * Called once by the Bridge's `register`. Every hook passes the drawing on untouched: the terminal
 * looks exactly as it would without the Bridge.
 *
 * @param on - The plugin's `on`.
 * @param isWatched - True while a HUD of this Session runs: only then are the model's responses counted.
 */
export function registerMirror(on: On, isWatched: () => boolean) {
  on('ui.render', { component: 'UserMessage' }, ($, e, next) => {
    capture(e.requestId, { component: 'UserMessage', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => {
    capture(e.requestId, { component: 'AssistantMessage', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'ToolUse' }, ($, e, next) => {
    capture(e.requestId, { component: 'ToolUse', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'ToolResult' }, ($, e, next) => {
    // The result block belongs to the tool row drawn just above it
    const row = M.captured.get(e.requestId)
    if (row?.component === 'ToolUse') {
      row.result = e.props
      M.stale.add(e.requestId)
      M.transcriptChanged = true
    }
    return next(e)
  })
  on('ui.render', { component: 'ToolGroup' }, ($, e, next) => {
    // A run with no calls draws nothing: it takes no place until a call joins it
    if (e.props.calls.length > 0 || M.captured.has(e.requestId)) capture(e.requestId, { component: 'ToolGroup', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'CommandOutput' }, ($, e, next) => {
    capture(e.requestId, { component: 'CommandOutput', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'TurnDuration' }, ($, e, next) => {
    capture(e.requestId, { component: 'TurnDuration', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'InfoNotice' }, ($, e, next) => {
    capture(e.requestId, { component: 'InfoNotice', props: e.props })
    return next(e)
  })
  on('ui.render', { component: 'Spinner' }, ($, e, next) => {
    setLive({ spinner: { word: maskSecrets(e.props.message ?? e.props.word), suffix: e.props.suffix, mode: e.props.mode } })
    return next(e)
  })
  on('ui.render', { component: 'PromptHint' }, ($, e, next) => {
    setLive({ hint: e.props.hint })
    return next(e)
  })
  on('ui.render', { component: 'SessionMode' }, ($, e, next) => {
    setLive({ modes: [...e.props.modes] })
    return next(e)
  })

  // How much the model has written in the running turn. Chunks and the response pass through as they are
  on('turn.step', async function* ($, e, next) {
    // A subagent's responses, and a Session nobody watches, pass untouched
    if (e.agentId !== undefined || e.turnId !== M.turn || !isWatched()) return yield* next(e)
    if (typeof e.effort === 'string') setLive({ effort: e.effort })
    const stream = next(e)
    let arrived = 0
    let counted = false
    try {
      for await (const chunk of stream) {
        const chars = chunkChars(chunk)
        arrived += chars
        M.arrivingLength += chars
        yield chunk
      }
      const response = await stream.result
      // The response is whole: its real token count takes the place of the estimate
      M.finishedLength += response.usage ? response.usage.output_tokens * 4 : arrived
      counted = true
      return response
    } finally {
      // Interrupted mid-response: what arrived still counts, as the estimate it was
      if (!counted) M.finishedLength += arrived
      M.arrivingLength = Math.max(0, M.arrivingLength - arrived)
    }
  })
}
