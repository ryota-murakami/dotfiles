import type { PromptRow as PromptRowData } from '@dw/protocol'
import { useState, type ReactNode } from 'react'

import { Markdown } from '../markdown/Markdown'
import { Dim, GLYPH, Gutter, RowLayout, themeColor, type ThemeColorName } from '../terminal'
import { formatDuration } from './duration'

/** Longest prompt that goes through the markdown renderer; longer ones are drawn as plain text. */
const MARKDOWN_LIMIT = 4000
/** Longer than this, a prompt is cut to its head and tail. */
const CUT_LIMIT = 10_000
/** Characters kept at each end of a cut prompt. */
const KEPT = 2500

const RAINBOW: readonly ThemeColorName[] = [
  'rainbow_red',
  'rainbow_orange',
  'rainbow_yellow',
  'rainbow_green',
  'rainbow_blue',
  'rainbow_indigo',
  'rainbow_violet',
]

/** Bullet colour of a finished background task, by how it ended. */
const STATUS_COLOR: Record<NonNullable<PromptRowData['status']>, ThemeColorName> = {
  completed: 'success',
  failed: 'error',
  killed: 'warning',
}

/**
 * Plain text in which each letter of the keyword `ultrathink` has its own rainbow colour.
 *
 * Why it exists: long prompts, and prompts that contain the keyword, skip the markdown renderer in the
 * terminal and are drawn as plain text, with the keyword's letters coloured in turn. Called by
 * {@link PromptText}.
 *
 * @param props.text - The prompt as typed.
 */
function PlainWithRainbow({ text }: { text: string }) {
  const parts = text.split(/(ultrathink)/i)
  return (
    <>
      {parts.map((part, index) =>
        // Odd parts are the keyword matches
        index % 2 === 1 ? (
          <span key={index}>
            {[...part].map((letter, position) => (
              <span
                key={position}
                style={{ color: themeColor(RAINBOW[position % RAINBOW.length] ?? 'text') }}
              >
                {letter}
              </span>
            ))}
          </span>
        ) : (
          part
        ),
      )}
    </>
  )
}

/** The text of a prompt: markdown in prompt mode when short, plain when long or when it has the keyword. */
function PromptText({ text }: { text: string }) {
  const hasKeyword = /ultrathink/i.test(text)
  if (text.length <= MARKDOWN_LIMIT && !hasKeyword) return <Markdown source={text} mode="prompt" />
  // Over the cut limit only the head and the tail stay, with a titled rule between them
  if (text.length > CUT_LIMIT) {
    const hidden = text.slice(KEPT, text.length - KEPT)
    const lines = hidden.split('\n').length
    const kb = Math.max(1, Math.round(hidden.length / 1024))
    const title = lines > 1 ? `(${lines} lines, ~${kb} KB hidden)` : `(~${kb} KB hidden)`
    return (
      <>
        <PlainWithRainbow text={text.slice(0, KEPT)} />
        <div className="prompt-rule">{title}</div>
        <PlainWithRainbow text={text.slice(text.length - KEPT)} />
      </>
    )
  }
  return <PlainWithRainbow text={text} />
}

/** The echo of what the user (or the HUD, or a plugin) sent: a pointer, the text, a grey background. */
function UserPrompt({ row, addMargin }: { row: PromptRowData; addMargin: boolean }) {
  return (
    <div className={addMargin ? 'row-margin' : undefined}>
      <div className="prompt">
        <span className="prompt-pointer" aria-label="you:">
          {GLYPH.pointer}
        </span>
        <div className="prompt-text">
          <PromptText text={row.text} />
        </div>
      </div>
    </div>
  )
}

/** A dim `› …` line: what the row above or inside a prompt says about where it came from. */
function FromLine({ children, addMargin = true }: { children: ReactNode; addMargin?: boolean }) {
  return (
    <RowLayout marker={GLYPH.pointerSmall} markerColor="var(--inactive)" addMargin={addMargin}>
      <Dim>{children}</Dim>
    </RowLayout>
  )
}

/** A background task's notification: a bullet coloured by how it ended, the summary, a dim detail. */
function TaskNotification({ row }: { row: PromptRowData }) {
  const color = themeColor(row.status ? STATUS_COLOR[row.status] : 'text')
  return (
    <RowLayout markerColor={color}>
      <span>{row.text}</span>
      {row.durationMs === undefined ? null : <Dim>{` · ${formatDuration(row.durationMs)}`}</Dim>}
    </RowLayout>
  )
}

/** A message from another agent: one dim line that a click opens into the message. */
function PeerMessage({ row }: { row: PromptRowData }) {
  const [isOpen, setIsOpen] = useState(false)
  const sender = row.from ? `@${row.from}` : 'another agent'
  if (isOpen) {
    return (
      <div>
        <FromLine>{`Message from ${row.from ?? 'another agent'}`}</FromLine>
        <Gutter>{row.text}</Gutter>
      </div>
    )
  }
  return (
    <div
      className="row-clickable"
      onClick={() => setIsOpen(true)}
      role="button"
      tabIndex={0}
      onKeyDown={(event) => event.key === 'Enter' && setIsOpen(true)}
    >
      <FromLine>{`Message from ${sender} (ctrl+o to expand)`}</FromLine>
    </div>
  )
}

/**
 * A Prompt row, by where it came from.
 *
 * Why it exists: the terminal draws the user's own prompt as `❯ text` on a grey background, a prompt
 * from a plugin (the HUD's Input box sends with origin `plugin`) under a dim `› From the … plugin`
 * line, a background task's notification as a coloured bullet with its summary, and a message from
 * another agent as one collapsed dim line. Any other origin is drawn as the user's own. Drawn by
 * {@link RowView} for a `prompt` Row.
 *
 * @param props.row - The Row.
 */
export function PromptRow({ row }: { row: PromptRowData }) {
  switch (row.origin) {
    case 'task-notification':
      return <TaskNotification row={row} />
    case 'peer':
      return <PeerMessage row={row} />
    case 'plugin':
      // The prompt hangs right under its "From" line, as one unit
      return row.from ? (
        <div>
          <FromLine>{`From the ${row.from} plugin`}</FromLine>
          <UserPrompt row={row} addMargin={false} />
        </div>
      ) : (
        <UserPrompt row={row} addMargin />
      )
    default:
      return <UserPrompt row={row} addMargin />
  }
}
