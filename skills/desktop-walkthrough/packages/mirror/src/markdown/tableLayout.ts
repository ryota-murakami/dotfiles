import { displayWidth, wrapLines } from '../terminal/width'

/** How a table is drawn: as a grid with these column widths (in columns), or one line per cell. */
export type TableLayout = { kind: 'grid'; widths: number[] } | { kind: 'vertical' }

/** The narrowest a column of a grid table may be. */
const MIN_COLUMN = 3
/** A cell taller than this many lines sends the table to the vertical layout. */
const MAX_CELL_LINES = 4

/** Sum of numbers. */
function sum(values: number[]): number {
  return values.reduce((total, value) => total + value, 0)
}

/** Width of the longest line of a text. */
function longestLine(text: string): number {
  return Math.max(0, ...text.split('\n').map(displayWidth))
}

/** Width of the longest word of a text. */
function longestWord(text: string): number {
  return Math.max(0, ...text.split(/\s+/).map(displayWidth))
}

/**
 * Decide how a table fits the page, by the terminal's algorithm (messages.md, section 4.8).
 *
 * Why it exists: Claude Code gives each column its natural width when the table fits, shares the room
 * by longest word when it nearly fits, narrows the columns to a common cap when it does not, and falls
 * back to one line per cell when a cell would need more than four lines. The Mirror, narrower than a
 * terminal, meets the fallback often, so it follows the same steps. Called by the table renderer.
 *
 * @param rows - Plain text of every cell, header row first.
 * @param columns - The page's width in columns; the table gets `columns - 4`.
 * @returns The grid with its column widths, or `vertical`.
 */
export function layoutTable(rows: readonly (readonly string[])[], columns: number): TableLayout {
  const count = Math.max(1, ...rows.map((row) => row.length))
  const available = columns - 4
  // Each column costs two pads and a bar, and the grid one more bar
  const frame = 1 + 3 * count
  const budget = Math.max(available - frame, MIN_COLUMN * count)

  const column = (index: number) => rows.map((row) => row[index] ?? '')
  const natural = Array.from({ length: count }, (_, index) =>
    Math.max(MIN_COLUMN, ...column(index).map(longestLine)),
  )
  const words = Array.from({ length: count }, (_, index) =>
    Math.max(MIN_COLUMN, ...column(index).map(longestWord)),
  )

  let widths: number[]
  if (sum(natural) <= budget) {
    // Everything fits at its natural width
    widths = natural
  } else if (sum(words) <= budget) {
    // Start at the longest word and share the leftover in proportion to what each column wants more
    const wanted = natural.map((width, index) => width - (words[index] ?? 0))
    const leftover = budget - sum(words)
    widths = words.map((width, index) => width + Math.floor((leftover * (wanted[index] ?? 0)) / sum(wanted)))
  } else {
    // Narrow every column to the largest common cap that fits
    let cap = Math.max(...natural)
    while (cap > MIN_COLUMN && sum(natural.map((width) => Math.min(width, cap))) > budget) cap -= 1
    widths = natural.map((width) => Math.min(width, cap))
  }

  // A cell that needs more than four lines, or a grid wider than the room, falls back
  const tooTall = rows.some((row) =>
    row.some((cell, index) => wrapLines(cell, widths[index] ?? MIN_COLUMN).length > MAX_CELL_LINES),
  )
  if (tooTall || sum(widths) + frame > available) return { kind: 'vertical' }
  return { kind: 'grid', widths }
}
