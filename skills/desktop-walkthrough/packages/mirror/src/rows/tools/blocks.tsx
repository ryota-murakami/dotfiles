/**
 * The small drawing parts every tool result is made of: bold counts, the `… +N lines (ctrl+o to
 * expand)` hint and a block of output that stops after a few rows.
 *
 * Why it exists: Bash output, MCP text, errors and previews all end the same way when they are long,
 * and the Mirror, which cannot expand, has to draw that ending as the terminal does. Used by the
 * result components of the tool rows.
 */
import type { ReactNode } from 'react'

import { Dim, wrapLines, type DimTone } from '../../terminal'
import type { ReadText } from './data'
import { nounFor } from './format'

/** A count or a name the terminal draws bold inside a plain sentence. */
export function Strong({ children }: { children: ReactNode }) {
  return <strong className="tool-strong">{children}</strong>
}

/**
 * The hint's wording.
 *
 * @param hidden - How many units are left out.
 * @param hiddenChars - Characters left out; at 1000 or more the hint adds `(~K KB)`.
 * @param unit - The unit counted; `line` when omitted.
 * @returns For example `… +21 lines (ctrl+o to expand)` or `… +89 lines (~7 KB) (ctrl+o to expand)`.
 */
export function expandHintText(hidden: number, hiddenChars = 0, unit = 'line'): string {
  const size = hiddenChars >= 1000 ? ` (~${Math.max(1, Math.round(hiddenChars / 1000))} KB)` : ''
  return `… +${hidden} ${nounFor(hidden, unit)}${size} (ctrl+o to expand)`
}

/**
 * The line that says how much a clipped block left out.
 *
 * Why it exists: the terminal ends a long result with it; the Mirror draws the same line (it cannot
 * expand, but the line reads as the terminal's).
 *
 * @param props.hidden - How many units are left out.
 * @param props.hiddenChars - Characters left out.
 * @param props.unit - The unit counted.
 * @param props.tone - The dim the surrounding result uses: `faint` under Bash, `inactive` elsewhere.
 */
export function ExpandHint({
  hidden,
  hiddenChars,
  unit,
  tone = 'inactive',
}: {
  hidden: number
  hiddenChars?: number
  unit?: string
  tone?: DimTone
}) {
  return (
    <div>
      <Dim tone={tone}>{expandHintText(hidden, hiddenChars, unit)}</Dim>
    </div>
  )
}

/** The escape sequences of coloured terminal output (colours, underline, cursor moves). */
const ESCAPES = new RegExp(`${String.fromCharCode(27)}\\[[0-9;?]*[ -/]*[@-~]`, 'g')

/**
 * Clean an output text for drawing: no escape codes, no trailing white space on a row or at the end.
 *
 * @param text - Output as the command printed it.
 * @returns The text with the escapes removed.
 */
export function cleanOutput(text: string): string {
  return text
    .replaceAll(ESCAPES, '')
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((row) => row.trimEnd())
    .join('\n')
    .trimEnd()
}

/**
 * Re-print output made only of one-line JSON values with a 2-space indent, as the terminal does.
 *
 * @param text - A whole output text (not a clipped one).
 * @returns The re-printed text, or the text itself when a line is no JSON object or array or the text is long.
 */
export function prettyJsonLines(text: string): string {
  if (text.length >= 10_000) return text
  const lines = text.split('\n').filter((line) => line.trim() !== '')
  if (lines.length === 0) return text
  const printed: string[] = []
  for (const line of lines) {
    const trimmed = line.trim()
    if (!/^[[{]/.test(trimmed)) return text
    try {
      printed.push(JSON.stringify(JSON.parse(trimmed), null, 2))
    } catch {
      return text
    }
  }
  return printed.join('\n')
}

/** What {@link ClampedText} takes. */
export type ClampedTextProps = {
  /** The text, whole or clipped. */
  text: ReadText
  /** Columns a row may take before the terminal wraps it. */
  width: number
  /** Rows shown before the hint. */
  limit: number
  /** True where exactly one row over the limit is shown whole instead of `+1 line` (Bash output). */
  isLenient?: boolean
  /** The class of the rows: `tool-error` or `tool-warning` colour them. */
  className?: string
  /** The dim of the hint. */
  hintTone?: DimTone
}

/**
 * Output that stops after a few rows and says how much it left out.
 *
 * Why it exists: Bash and MCP output shows 3 rows, an error 10, then `… +N lines`; rows are counted
 * after wrapping at the block's width, and a block over the limit by exactly one row is shown whole.
 * Used by the Bash, MCP, generic and error results.
 *
 * @param props - See {@link ClampedTextProps}.
 */
export function ClampedText({
  text,
  width,
  limit,
  isLenient = false,
  className,
  hintTone,
}: ClampedTextProps) {
  const body = text.isClipped ? cleanOutput(text.text) : prettyJsonLines(cleanOutput(text.text))
  const rows = wrapLines(body, Math.max(width, 10))
  // A clipped text has more lines than the Bridge kept: they count as rows too
  const keptLines = body === '' ? 0 : body.split('\n').length
  const total = rows.length + (text.isClipped ? Math.max(0, text.lines - keptLines) : 0)
  const shown = isLenient && total === limit + 1 ? total : limit
  const visible = rows.slice(0, shown)
  const hidden = total - visible.length
  const hiddenChars = Math.max(0, text.chars - visible.join('\n').length)
  return (
    <>
      {visible.map((row, index) => (
        <div key={index} className={['tool-row', className].filter(Boolean).join(' ')}>
          {row}
        </div>
      ))}
      {hidden > 0 && <ExpandHint hidden={hidden} hiddenChars={hiddenChars} tone={hintTone ?? 'faint'} />}
    </>
  )
}
