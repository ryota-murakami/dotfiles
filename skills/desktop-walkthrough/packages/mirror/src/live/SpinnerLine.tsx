import type { LiveDocument } from '@dw/protocol'
import { useContext, useEffect, useState, type CSSProperties } from 'react'

import { formatDuration } from '../rows/duration'
import { Dim, displayWidth, themeColor, useColumns } from '../terminal'
import { ClockContext, useNow, useTurnClocks } from './clock'
import {
  BRACKET_AFTER_MS,
  REDUCED_MOTION_GLYPH,
  breathe,
  canStall,
  formatTokens,
  glyphAt,
  layoutBracket,
  lightCentre,
  splitLight,
  stallIntensity,
  stepShownLength,
  thinkingPulse,
  thinkingState,
  thinkingTint,
  thinkingWording,
  tickPeriodMs,
  tokensOfLength,
} from './spinnerRules'
import { useReducedMotion } from './useReducedMotion'

/**
 * A CSS colour that is `from` blended toward `to`.
 *
 * @param from - A CSS colour, the result at amount 0.
 * @param to - A CSS colour, the result at amount 1.
 * @param amount - 0..1.
 */
function blend(from: string, to: string, amount: number): string {
  const percent = Math.round(amount * 100)
  return `color-mix(in srgb, ${from} ${100 - percent}%, ${to} ${percent}%)`
}

/**
 * The shown length of the response: it chases the reported one in small steps, so the token figure
 * counts up instead of jumping.
 *
 * @param target - The length the HUD reported.
 * @param isStill - True in reduced motion: no animation, the figure is the reported one.
 * @returns The length to show.
 */
function useShownLength(target: number, isStill: boolean): number {
  const clock = useContext(ClockContext)
  const [shown, setShown] = useState(target)
  const isCaughtUp = shown === target
  useEffect(() => {
    if (isCaughtUp || isStill) return
    return clock.every(50, () => setShown((current) => stepShownLength(current, target)))
  }, [clock, isCaughtUp, isStill, target])
  return isStill ? target : shown
}

/** The word with its ellipsis: the data's suffix, unless the word already ends in one. */
function verbText(word: string, suffix: string): string {
  return /(…|\.\.\.)$/.test(word) ? word : word + suffix
}

/**
 * The Spinner line: the glyph, the verb with the light running over it and the bracketed status.
 *
 * Why it exists: it is how the Mirror shows that the agent works, for how long and how much it has
 * written, the way the terminal's own line does (docs/claude-code-tui/spinner-and-prompt.md, section
 * 1). Rendered by {@link LiveArea} while a turn runs and the live document names a spinner; it
 * redraws itself on the clock, at 50 ms while a request is sent and 100 ms otherwise.
 *
 * @param props.live - A live document with `isBusy` and a `spinner`.
 */
export function SpinnerLine({
  live,
}: {
  live: LiveDocument & { spinner: NonNullable<LiveDocument['spinner']> }
}) {
  const { spinner } = live
  const mode = spinner.mode
  const isStill = useReducedMotion()
  const columns = useColumns()
  const clocks = useTurnClocks(live)
  const shownLength = useShownLength(live.responseLength ?? 0, isStill)
  const isCounting = shownLength !== (live.responseLength ?? 0)
  const now = useNow(isStill ? 500 : isCounting ? 50 : tickPeriodMs(mode))

  const verb = verbText(spinner.word, spinner.suffix)
  const verbWidth = displayWidth(verb)

  // Stall: long silence turns the glyph and the verb red and stops the light
  const silence = clocks.lastGrowthAt === undefined ? 0 : now - clocks.lastGrowthAt
  const stall = canStall(mode) ? stallIntensity(silence) : 0

  // Thinking: the wording by how long, its pulse and its tint toward the warning colour
  const thinking = thinkingState(now, clocks.thinking)
  const thinkingMs = thinking.kind === 'thinking' ? thinking.thinkingMs : 0
  const tint = !isStill && thinking.kind === 'thinking' ? thinkingTint(thinkingMs) : 0

  // The base colour of the glyph and the verb: red by stall, yellow by long thinking
  const baseColour =
    stall > 0
      ? blend(themeColor('claude'), themeColor('error'), stall)
      : tint > 0
        ? blend(themeColor('claude'), themeColor('warning'), tint)
        : themeColor('claude')
  const glyphStyle: CSSProperties = {
    color: baseColour,
    ...(tint >= 0.5 && stall === 0 ? { fontWeight: 'bold' } : {}),
  }

  // The bracket's parts
  const elapsedMs = live.startedAt === undefined ? undefined : Math.max(0, now - live.startedAt)
  const tokenCount = tokensOfLength(shownLength)
  const thinkingText =
    thinking.kind === 'thinking'
      ? { text: thinkingWording(thinking.thinkingMs, live.effort), fallback: 'thinking' }
      : thinking.kind === 'thought-for'
        ? { text: `thought for ${thinking.seconds}s`, fallback: undefined }
        : undefined
  const hasBracket =
    thinkingText !== undefined || tokenCount > 0 || (elapsedMs !== undefined && elapsedMs > BRACKET_AFTER_MS)
  const layout = layoutBracket({
    columns,
    verbWidth,
    elapsed: hasBracket && elapsedMs !== undefined ? formatDuration(elapsedMs) : undefined,
    tokens:
      tokenCount > 0 ? `${mode === 'requesting' ? '↑' : '↓'} ${formatTokens(tokenCount)} tokens` : undefined,
    thinking: thinkingText,
  })
  const parts = [layout.elapsed, layout.tokens].filter((part): part is string => part !== undefined)

  // The thinking text is not dim: pulse between two greys, then tint toward the warning colour
  const thinkingColour =
    thinking.kind === 'thinking' && !isStill
      ? blend(
          blend(themeColor('inactive'), themeColor('inactiveShimmer'), thinkingPulse(now, thinkingMs)),
          themeColor('warning'),
          tint,
        )
      : themeColor('inactive')
  const thinkingStyle: CSSProperties = { color: thinkingColour }

  return (
    <div className="spinner-line" data-mode={mode} data-stall={stall}>
      <span
        className={isStill ? 'spinner-glyph spinner-pulse' : 'spinner-glyph'}
        style={isStill ? ({ '--spinner-base': baseColour } as CSSProperties) : glyphStyle}
        aria-hidden
      >
        {isStill ? REDUCED_MOTION_GLYPH : glyphAt(now)}
      </span>
      <div className="spinner-text">
        <Verb text={verb} mode={mode} now={now} baseColour={baseColour} hasLight={!isStill && stall === 0} />{' '}
        {layout.thinking !== undefined || parts.length > 0 ? (
          <>
            <span className="dim dim-inactive" style={layout.isThinkingAlone ? thinkingStyle : undefined}>
              (
            </span>
            {parts.map((part, index) => (
              <span key={part}>
                {index > 0 ? <Dim>{' · '}</Dim> : null}
                <Dim>{part}</Dim>
              </span>
            ))}
            {layout.thinking !== undefined ? (
              <>
                {parts.length > 0 ? <Dim>{' · '}</Dim> : null}
                <span className="spinner-thinking" style={thinkingStyle}>
                  {layout.thinking}
                </span>
              </>
            ) : null}
            <span className="dim dim-inactive" style={layout.isThinkingAlone ? thinkingStyle : undefined}>
              )
            </span>
          </>
        ) : null}
      </div>
    </div>
  )
}

/**
 * The verb, with the light running over it by mode, or breathing as a whole while a tool runs.
 *
 * @param props.text - The verb with its ellipsis.
 * @param props.mode - The spinner's mode: which way the light travels.
 * @param props.now - Milliseconds since 1970; the light's place is absolute, not from the turn's start.
 * @param props.baseColour - The colour of the cells the light is not on.
 * @param props.hasLight - False while stalled or in reduced motion.
 */
function Verb({
  text,
  mode,
  now,
  baseColour,
  hasLight,
}: {
  text: string
  mode: NonNullable<LiveDocument['spinner']>['mode']
  now: number
  baseColour: string
  hasLight: boolean
}) {
  if (!hasLight) return <span style={{ color: baseColour }}>{text}</span>
  // Tool use: no travelling light, the whole word breathes toward the light colour
  if (mode === 'tool-use') {
    return <span style={{ color: blend(baseColour, themeColor('claudeShimmer'), breathe(now)) }}>{text}</span>
  }
  const runs = splitLight(text, lightCentre(now, mode, displayWidth(text)))
  return (
    <>
      {runs.map((run, index) => (
        <span key={index} style={{ color: run.isLit ? themeColor('claudeShimmer') : baseColour }}>
          {run.text}
        </span>
      ))}
    </>
  )
}
