/**
 * The rules of the Spinner line as pure functions of time and numbers: which glyph, where the light
 * is, how red a stall is, what the thinking text says, how the token figure counts up and which parts
 * of the bracket fit.
 *
 * Why it exists: the rules are the part of the Spinner line that can be wrong without anyone seeing it
 * (a threshold, a unit, a format), so they live apart from the drawing and are covered by specs with
 * hard-coded moments. Called by {@link SpinnerLine}; the thresholds are those of
 * docs/claude-code-tui/spinner-and-prompt.md, section 1.
 */
import { cellWidth, displayWidth } from '../terminal'

import type { SpinnerMode } from '@dw/protocol'

/** The glyph frames the terminal cycles through, from the smallest to the largest. */
export const SPINNER_FRAMES = ['·', '✢', '✳', '✶', '✻', '✽'] as const

/** The single glyph that replaces the frames when the user asks for reduced motion. */
export const REDUCED_MOTION_GLYPH = '●'

/** Silence, in milliseconds, after which the Spinner line starts to turn red. */
export const STALL_AFTER_MS = 10_000

/** How long after the stall began the line is fully red. */
export const STALL_RAMP_MS = 10_000

/** When the thinking text starts to tint toward the warning colour, and when the tint is full. */
export const THINKING_TINT_FROM_MS = 10_000
export const THINKING_TINT_FULL_MS = 20_000

/** After this long in `thinking` the text starts to pulse. */
export const THINKING_PULSE_FROM_MS = 3000

/** Thinking shorter than this never switches to the `thought for` form. */
export const THOUGHT_FOR_MIN_MS = 2000

/** How long `thought for Ns` stays after thinking ended. */
export const THOUGHT_FOR_SHOWN_MS = 2000

/** The bracket is drawn on its own once the turn has run this long. */
export const BRACKET_AFTER_MS = 16_000

/**
 * Round a 0..1 amount to the eighths the terminal quantises its colour blends to.
 *
 * @param amount - A blend amount, clamped into 0..1.
 * @returns The nearest multiple of one eighth.
 */
export function quantise(amount: number): number {
  return Math.round(Math.min(Math.max(amount, 0), 1) * 8) / 8
}

/**
 * The glyph of the spinner at a moment: it rises from the smallest to the largest and falls back once
 * every two seconds, by wall-clock time (not from the start of the turn).
 *
 * @param nowMs - Milliseconds since 1970.
 * @returns One of {@link SPINNER_FRAMES}.
 */
export function glyphAt(nowMs: number): string {
  const index = Math.round((5 * (1 - Math.cos((2 * Math.PI * (nowMs % 2000)) / 2000))) / 2)
  return SPINNER_FRAMES[index] ?? SPINNER_FRAMES[0]
}

/**
 * How often the Spinner line redraws: twice as often while a request is being sent.
 *
 * @param mode - The spinner's mode.
 * @returns Milliseconds between two redraws.
 */
export function tickPeriodMs(mode: SpinnerMode): number {
  return mode === 'requesting' ? 50 : 100
}

/**
 * Where the light is over the verb: the column of its centre.
 *
 * It sweeps from ten cells outside one edge to ten cells outside the other and starts over: left to
 * right at one cell per 50 ms while `requesting`, right to left at one cell per 200 ms otherwise.
 *
 * @param nowMs - Milliseconds since 1970.
 * @param mode - The spinner's mode (not `tool-use`, which has no travelling light).
 * @param verbWidth - Columns of the verb with its ellipsis.
 * @returns The centre column; below 0 or past the verb while the light is outside it.
 */
export function lightCentre(nowMs: number, mode: SpinnerMode, verbWidth: number): number {
  const steps = verbWidth + 20
  if (mode === 'requesting') return (Math.floor(nowMs / 50) % steps) - 10
  return verbWidth + 10 - (Math.floor(nowMs / 200) % steps)
}

/** A piece of the verb and whether the light is on it. */
export type LitRun = { text: string; isLit: boolean }

/**
 * Cut the verb into runs by whether the light is on them: the cells whose first column lies within
 * one column of the centre are lit.
 *
 * @param text - The verb with its ellipsis.
 * @param centre - The light's centre column from {@link lightCentre}.
 * @returns Runs in order; their texts join to the verb.
 */
export function splitLight(text: string, centre: number): LitRun[] {
  const runs: LitRun[] = []
  let column = 0
  for (const char of text) {
    const isLit = column >= centre - 1 && column <= centre + 1
    const last = runs[runs.length - 1]
    if (last && last.isLit === isLit) last.text += char
    else runs.push({ text: char, isLit })
    column += cellWidth(char.codePointAt(0) ?? 0)
  }
  return runs
}

/**
 * How far the whole verb has breathed toward the light colour while a tool runs: a sine of period
 * two seconds, in eighths.
 *
 * @param nowMs - Milliseconds since 1970.
 * @returns 0..1 in steps of one eighth.
 */
export function breathe(nowMs: number): number {
  return quantise((Math.sin((Math.PI * nowMs) / 1000) + 1) / 2)
}

/**
 * How red a stall is: nothing for the first ten seconds of silence, full twenty seconds in.
 *
 * @param silenceMs - Time since the token figure last grew.
 * @returns 0..1 in steps of one eighth.
 */
export function stallIntensity(silenceMs: number): number {
  return quantise((silenceMs - STALL_AFTER_MS) / STALL_RAMP_MS)
}

/**
 * Whether the stall rule applies in a mode: a turn that is running a tool or thinking is not stalled
 * for being quiet.
 *
 * @param mode - The spinner's mode.
 */
export function canStall(mode: SpinnerMode): boolean {
  return mode !== 'tool-use' && mode !== 'thinking'
}

/**
 * How far the thinking tint toward the warning colour has come: nothing for ten seconds, full at twenty.
 *
 * @param thinkingMs - How long the mode has been `thinking`.
 * @returns 0..1 in steps of one eighth.
 */
export function thinkingTint(thinkingMs: number): number {
  return quantise((thinkingMs - THINKING_TINT_FROM_MS) / (THINKING_TINT_FULL_MS - THINKING_TINT_FROM_MS))
}

/**
 * How far the thinking text has pulsed toward its lighter grey: a sine of period two seconds that
 * begins after three seconds of thinking.
 *
 * @param nowMs - Milliseconds since 1970.
 * @param thinkingMs - How long the mode has been `thinking`.
 * @returns 0..1 in steps of one eighth; 0 before the pulse starts.
 */
export function thinkingPulse(nowMs: number, thinkingMs: number): number {
  if (thinkingMs < THINKING_PULSE_FROM_MS) return 0
  return quantise((Math.sin((Math.PI * nowMs) / 1000) + 1) / 2)
}

/**
 * The thinking wording by how long the thinking has run, with the effort appended.
 *
 * @param thinkingMs - How long the mode has been `thinking`.
 * @param effort - The turn's effort level, when the model has one.
 * @returns For example `thinking`, `still thinking with max effort`.
 */
export function thinkingWording(thinkingMs: number, effort: string | undefined): string {
  const word =
    thinkingMs >= 45_000
      ? 'deep in thought'
      : thinkingMs >= 30_000
        ? 'thinking some more'
        : thinkingMs >= 20_000
          ? 'thinking more'
          : thinkingMs >= 10_000
            ? 'still thinking'
            : 'thinking'
  return effort ? `${word} with ${effort.toLowerCase()} effort` : word
}

/** What the thinking part of the bracket shows right now. */
export type ThinkingState =
  /** The mode is `thinking`: the wording, by how long. */
  | { kind: 'thinking'; thinkingMs: number }
  /** Thinking has just ended: `thought for Ns`. */
  | { kind: 'thought-for'; seconds: number }
  | { kind: 'none' }

/**
 * Decide what the thinking part shows: the live wording while the mode is `thinking`, then, for two
 * seconds, how long the thought took (only if it lasted two seconds or more).
 *
 * @param nowMs - Milliseconds since 1970.
 * @param thinking - When the mode became `thinking` and, if it has ended, when it ended.
 * @returns The state to draw.
 */
export function thinkingState(
  nowMs: number,
  thinking: { start: number; end: number | undefined } | undefined,
): ThinkingState {
  if (!thinking) return { kind: 'none' }
  if (thinking.end === undefined) return { kind: 'thinking', thinkingMs: nowMs - thinking.start }
  // A short thought keeps the plain wording until it has lasted two seconds, then the label follows
  const labelFrom = Math.max(thinking.end, thinking.start + THOUGHT_FOR_MIN_MS)
  if (nowMs < labelFrom) return { kind: 'thinking', thinkingMs: nowMs - thinking.start }
  if (nowMs < labelFrom + THOUGHT_FOR_SHOWN_MS) {
    return { kind: 'thought-for', seconds: Math.max(1, Math.round((thinking.end - thinking.start) / 1000)) }
  }
  return { kind: 'none' }
}

/**
 * A token count the way the terminal words it: whole under a thousand, then one decimal and a
 * lower-case suffix (`1.2k`, `84.6k`, `1.2m`).
 *
 * @param tokens - A whole number of tokens.
 */
export function formatTokens(tokens: number): string {
  if (tokens < 1000) return String(Math.max(0, Math.round(tokens)))
  return new Intl.NumberFormat('en-US', {
    notation: 'compact',
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })
    .format(tokens)
    .toLowerCase()
}

/**
 * The token figure the line shows for a length in the terminal's characters (four per token).
 *
 * @param length - The shown `responseLength`.
 * @returns The wording without the arrow, for example `5.2k`.
 */
export function tokensOfLength(length: number): number {
  return Math.round(length / 4)
}

/**
 * One 50 ms step of the counting animation: the shown length chases the real one.
 *
 * @param shown - The length drawn now.
 * @param target - The length the HUD reported.
 * @returns The next shown length: a step of 3 below a gap of 70, a sixth of the gap (at least 8)
 *   below 200, 50 otherwise; at once for a gap over 2000 or when the length went down.
 */
export function stepShownLength(shown: number, target: number): number {
  const gap = target - shown
  if (gap <= 0 || gap > 2000) return target
  const step = gap < 70 ? 3 : gap < 200 ? Math.max(8, Math.ceil(gap * 0.15)) : 50
  return Math.min(target, shown + step)
}

/** The parts of the bracket that fit, in the order they are drawn. */
export type BracketLayout = {
  elapsed: string | undefined
  tokens: string | undefined
  thinking: string | undefined
  /** True when the thinking text stands alone: its parentheses take its colour. */
  isThinkingAlone: boolean
}

/**
 * Decide which parts of the bracket fit the width, dropping the least important first: the thinking
 * text is kept longest, then the time, then the tokens.
 *
 * @param input.columns - Width of the line in columns.
 * @param input.verbWidth - Columns of the verb with its ellipsis.
 * @param input.elapsed - The time wording, when the bracket shows time.
 * @param input.tokens - The token wording with its arrow, when there are tokens.
 * @param input.thinking - The thinking wording and the plain fallback for a narrow line.
 * @returns The parts to draw.
 */
export function layoutBracket(input: {
  columns: number
  verbWidth: number
  elapsed: string | undefined
  tokens: string | undefined
  thinking: { text: string; fallback: string | undefined } | undefined
}): BracketLayout {
  const available = input.columns - (input.verbWidth + 2) - 5
  let used = 0
  let thinking: string | undefined
  let elapsed: string | undefined
  let tokens: string | undefined

  // Thinking first: its full wording, else the plain one, else nothing
  if (input.thinking) {
    for (const candidate of [input.thinking.text, input.thinking.fallback]) {
      if (candidate !== undefined && displayWidth(candidate) <= available) {
        thinking = candidate
        used = displayWidth(candidate)
        break
      }
    }
  }
  // Each next part needs its own width plus the separator when something precedes it
  if (input.elapsed !== undefined) {
    const needed = used + (used > 0 ? 3 : 0) + displayWidth(input.elapsed)
    if (needed <= available) {
      elapsed = input.elapsed
      used = needed
    }
  }
  if (input.tokens !== undefined) {
    const needed = used + (used > 0 ? 3 : 0) + displayWidth(input.tokens)
    // Tokens only while everything before them is still there
    if (needed <= available && (input.elapsed === undefined || elapsed !== undefined)) {
      tokens = input.tokens
    }
  }
  return { elapsed, tokens, thinking, isThinkingAlone: thinking !== undefined && !elapsed && !tokens }
}
