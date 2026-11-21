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
/** The terminal draws this much of a line a plugin logged. */
const LOG_CHARS = 2000
/** Thinking that ended this long ago and that no run took belongs to no run that appears now. */
const THOUGHT_FRESH_MS = 5000
/** A run drawn this little before its thinking was known to have ended still takes that thinking. */
const THOUGHT_SLACK_MS = 300

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
  | { component: 'ToolGroup'; props: RenderPropsOf['ToolGroup']; thoughtMs?: number }
  | { component: 'Log'; plugin: string; text: string }
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
  /** Which folded run holds each tool call: the call's id, then the run's row id. */
  foldedInto: new Map<string, string>(),
  /** The run that is live now: the model's next thinking and calls join it. */
  liveGroup: undefined as string | undefined,
  /** The run that was drawn first most recently, and when. */
  newestGroup: undefined as { id: string; at: number } | undefined,
  /** Thinking of the main loop that ended and that no run has taken yet. */
  pendingThought: undefined as { ms: number; at: number } | undefined,
  /** Lines plugins logged so far: each gets a row id of its own. */
  logCount: 0,
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
      const { props, thoughtMs } = captured
      // A run that holds neither a call nor thinking the Bridge timed has nothing to show here
      if (props.calls.length === 0 && thoughtMs === undefined) return undefined
      return {
        kind: 'tool-group',
        id,
        calls: props.calls.map(toolCall),
        isActive: props.isActive,
        ...(thoughtMs === undefined ? {} : { thoughtMs }),
      }
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
    case 'Log':
      return { kind: 'log', id, plugin: captured.plugin, text: maskSecrets(captured.text.slice(0, LOG_CHARS)) }
  }
}

/** Forget a row. */
function drop(id: string) {
  // A run that goes takes its hold on its calls with it
  if (M.captured.get(id)?.component === 'ToolGroup') {
    for (const [callId, run] of M.foldedInto) if (run === id) M.foldedInto.delete(callId)
    if (M.liveGroup === id) M.liveGroup = undefined
    if (M.newestGroup?.id === id) M.newestGroup = undefined
  }
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

/** Put a row where another stood: right before the row that followed that one, or last. */
function moveBefore(id: string, follower: string | undefined) {
  const order = M.placement.order.filter(row => row !== id)
  const at = follower === undefined ? -1 : order.indexOf(follower)
  if (at === -1) order.push(id)
  else order.splice(at, 0, id)
  M.placement.order = order
}

/** The row that follows a row, to give its place to another with {@link moveBefore}. */
function followerOf(id: string): string | undefined {
  const at = M.placement.order.indexOf(id)
  return at === -1 ? undefined : M.placement.order[at + 1]
}

/** Add thinking to a run's total. */
function addThought(id: string, ms: number) {
  const run = M.captured.get(id)
  if (run?.component !== 'ToolGroup') return
  run.thoughtMs = (run.thoughtMs ?? 0) + ms
  M.stale.add(id)
  M.transcriptChanged = true
}

/**
 * A block of the main loop's thinking ended: give its length to the run that holds it.
 *
 * Why it exists: the terminal's line for a folded run says how long the model thought inside it
 * (`Thought for 8s, read 2 files`), but the run's drawing event carries only its calls. The terminal
 * adds a thinking block to the live run, or opens a run for it; the Bridge follows the same rule
 * with the length it timed. Called by the `turn.step` hook of {@link registerMirror}.
 *
 * @param ms - How long the block took.
 * @param endedAt - When it ended, in milliseconds since 1970.
 */
export function noteThought(ms: number, endedAt: number) {
  if (M.liveGroup !== undefined && M.captured.get(M.liveGroup)?.component === 'ToolGroup') return addThought(M.liveGroup, ms)
  // The run the terminal opened for this block may have been drawn already
  const newest = M.newestGroup
  if (newest !== undefined && newest.at >= endedAt - THOUGHT_SLACK_MS && M.captured.get(newest.id)?.component === 'ToolGroup') {
    return addThought(newest.id, ms)
  }
  const waiting = M.pendingThought
  const isFresh = waiting !== undefined && endedAt - waiting.at <= THOUGHT_FRESH_MS
  M.pendingThought = { ms: (isFresh ? waiting.ms : 0) + ms, at: endedAt }
}

/**
 * Keep a folded run the terminal just drew, in the place of what it folds.
 *
 * Why it exists: a run is not one row from start to end. A call is first drawn as a row of its own
 * while its input arrives and joins a run after; and a run is drawn under one id while the response
 * streams and under another once it is whole, the first never drawn again. Kept as they came, the
 * Mirror would show the call twice and the run twice. Called by the `ToolGroup` hook of
 * {@link registerMirror}.
 *
 * @param id - The run's row id.
 * @param props - What the terminal handed the run's line.
 */
export function captureGroup(id: string, props: RenderPropsOf['ToolGroup']) {
  // Unfolded (verbose, the ctrl+o view): each call is its own row there; the Mirror keeps the main view
  if (props.isExpanded) return
  const now = Date.now()
  const known = M.captured.get(id)
  const isNew = known === undefined
  let thoughtMs = known?.component === 'ToolGroup' ? known.thoughtMs : undefined
  // Where the run goes when it is new: the place of the first row it replaces
  let spot: { follower: string | undefined } | undefined
  for (const call of props.calls) {
    const callId = call.tool_use_id
    if (callId === undefined) continue
    // The same run under its earlier id: this drawing replaces it and keeps its thinking
    const earlier = M.foldedInto.get(callId)
    const twin = earlier === undefined || earlier === id ? undefined : M.captured.get(earlier)
    if (earlier !== undefined && twin?.component === 'ToolGroup') {
      if (twin.thoughtMs !== undefined) thoughtMs = (thoughtMs ?? 0) + twin.thoughtMs
      spot ??= { follower: followerOf(earlier) }
      drop(earlier)
    }
    // The call's own row, drawn while its input arrived: the run shows the call now
    if (M.captured.get(callId)?.component === 'ToolUse') {
      spot ??= { follower: followerOf(callId) }
      drop(callId)
    }
    M.foldedInto.set(callId, id)
  }
  capture(id, { component: 'ToolGroup', props, ...(thoughtMs === undefined ? {} : { thoughtMs }) })
  if (isNew) {
    if (spot !== undefined) moveBefore(id, spot.follower)
    // Two live runs never stand next to each other: a live run right above this one is this run's earlier id
    const at = M.placement.order.indexOf(id)
    const above = at > 0 ? M.placement.order[at - 1] : undefined
    const aboveRun = above === undefined ? undefined : M.captured.get(above)
    if (above !== undefined && aboveRun?.component === 'ToolGroup' && aboveRun.props.isActive) {
      if (aboveRun.thoughtMs !== undefined) addThought(id, aboveRun.thoughtMs)
      drop(above)
    }
    M.newestGroup = { id, at: now }
  }
  // Thinking that ended before the terminal drew the run it belongs to
  const waiting = M.pendingThought
  if (waiting !== undefined && (isNew ? now - waiting.at <= THOUGHT_FRESH_MS : M.liveGroup === id)) {
    addThought(id, waiting.ms)
    M.pendingThought = undefined
  }
  if (props.isActive) M.liveGroup = id
  else if (M.liveGroup === id) M.liveGroup = undefined
}

/**
 * Keep a tool call's own row the terminal just drew.
 *
 * Called by the `ToolUse` hook of {@link registerMirror}. A call that a folded run holds is drawn
 * as a row of its own in two cases only, told apart here: the ctrl+o view (or verbose) draws every
 * call in full, which the Mirror does not follow; the main view draws it when it left its run.
 *
 * @param id - The call's id, which is its row's id.
 * @param props - What the terminal handed the row.
 */
export function captureTool(id: string, props: RenderPropsOf['ToolUse']) {
  if (M.foldedInto.has(id)) {
    // Drawn in full by the ctrl+o view: the Mirror keeps the main view's fold
    if (props.isExpanded) return
    // Drawn as a row of its own in the main view: it left its run
    M.foldedInto.delete(id)
  }
  capture(id, { component: 'ToolUse', props })
}

/**
 * The Rows as they stand now, oldest first.
 *
 * Called by {@link flushMirror} when the Transcript changed. Cutting and masking happen here, for
 * the rows whose data changed since the last call.
 */
export function currentRows(): Row[] {
  for (const id of M.stale) {
    const captured = M.captured.get(id)
    const row = captured === undefined ? undefined : buildRow(id, captured)
    if (row === undefined) M.built.delete(id)
    else M.built.set(id, row)
  }
  M.stale.clear()
  return M.placement.order.flatMap(id => {
    const row = M.built.get(id)
    return row === undefined ? [] : [row]
  })
}

/** Forget every row and every run: a Session's Mirror starts empty. Called by the specs between cases. */
export function resetMirror() {
  M.captured.clear()
  M.built.clear()
  M.stale.clear()
  M.placement = newPlacement()
  M.dropped = 0
  M.foldedInto.clear()
  M.liveGroup = undefined
  M.newestGroup = undefined
  M.pendingThought = undefined
  M.logCount = 0
  M.transcriptChanged = true
}

/** Change the live state and remember that it has to be written. */
function setLive(change: Partial<LiveDocument>) {
  M.live = { ...M.live, ...change }
}

/** Note the Session's permission mode from the input of a classic hook, which always carries it. */
function hearMode(e: { permission_mode?: string }) {
  if (typeof e.permission_mode === 'string' && e.permission_mode !== M.live.permissionMode) setLive({ permissionMode: e.permission_mode })
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
  M.pendingThought = undefined
  // The spinner of the turn before is not this turn's
  const { spinner: _spinner, effort: _effort, ...rest } = M.live
  M.live = { ...rest, isBusy: true, startedAt: Date.now(), responseLength: 0 }
}

/** The turn of the main loop ended. Called by the Bridge's `turn.complete` hook. */
export function noteTurnComplete() {
  M.turn = undefined
  M.turnEndedAt = Date.now()
  M.pendingThought = undefined
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
      const transcript: TranscriptDocument = { v: 1, sessionId, dropped: M.dropped, rows: currentRows() }
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
    captureTool(e.requestId, e.props)
    return next(e)
  })
  on('ui.render', { component: 'ToolResult' }, ($, e, next) => {
    // The result block belongs to the tool row drawn just above it; a folded call has no row
    const row = M.foldedInto.has(e.requestId) ? undefined : M.captured.get(e.requestId)
    if (row?.component === 'ToolUse') {
      row.result = e.props
      M.stale.add(e.requestId)
      M.transcriptChanged = true
    }
    return next(e)
  })
  on('ui.render', { component: 'ToolGroup' }, ($, e, next) => {
    captureGroup(e.requestId, e.props)
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

  // A line a plugin writes into the transcript is a row of the terminal's, drawn with the plugin's name
  on('ui.log', ($, e, next) => {
    if (e.to === 'transcript') {
      M.logCount += 1
      capture(`log-${M.logCount}`, { component: 'Log', plugin: next.origin.plugin, text: e.text })
    }
    return next(e)
  })

  // The permission mode opens the hint line; Claude Code tells it with every classic hook's input
  on('classic.UserPromptSubmit', ($, e, next) => (hearMode(e), next(e)))
  on('classic.PostToolUse', ($, e, next) => (hearMode(e), next(e)))
  on('classic.Stop', ($, e, next) => (hearMode(e), next(e)))

  // How much the model has written in the running turn. Chunks and the response pass through as they are
  on('turn.step', async function* ($, e, next) {
    // A subagent's responses, and a Session nobody watches, pass untouched
    if (e.agentId !== undefined || e.turnId !== M.turn || !isWatched()) return yield* next(e)
    if (typeof e.effort === 'string') setLive({ effort: e.effort })
    const stream = next(e)
    let arrived = 0
    let counted = false
    // A thinking block runs from the engine's item that opens it to the one that closes it: the first
    // and the last engine items between two pieces of content
    let gapStart: number | undefined = Date.now()
    let gapEnd: number | undefined
    let thinking: { index: number; startedAt: number } | undefined
    const endThinking = (at: number) => {
      if (thinking === undefined) return
      noteThought(Math.max(1, Math.round(at - thinking.startedAt)), at)
      thinking = undefined
    }
    try {
      for await (const chunk of stream) {
        const now = Date.now()
        if (chunk.kind === 'engine') {
          gapStart ??= now
          gapEnd = now
        } else {
          if (chunk.kind === 'thinking') {
            // Another block of thinking: the one before ended at the items between them
            if (thinking !== undefined && thinking.index !== chunk.index) endThinking(gapEnd ?? now)
            thinking ??= { index: chunk.index, startedAt: gapStart ?? now }
          } else {
            endThinking(gapEnd ?? now)
          }
          gapStart = undefined
          gapEnd = undefined
        }
        const chars = chunkChars(chunk)
        arrived += chars
        M.arrivingLength += chars
        yield chunk
      }
      endThinking(gapEnd ?? Date.now())
      const response = await stream.result
      // The response is whole: its real token count takes the place of the estimate
      M.finishedLength += response.usage ? response.usage.output_tokens * 4 : arrived
      counted = true
      return response
    } finally {
      // Interrupted while thinking: the block ended there
      endThinking(Date.now())
      // Interrupted mid-response: what arrived still counts, as the estimate it was
      if (!counted) M.finishedLength += arrived
      M.arrivingLength = Math.max(0, M.arrivingLength - arrived)
    }
  })
}
