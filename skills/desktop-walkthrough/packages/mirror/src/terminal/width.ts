/**
 * Terminal cell arithmetic: how many columns a text takes and where a terminal would break it.
 *
 * Why it exists: Claude Code lays a table out in whole columns, so the Mirror has to count in the same
 * unit (East Asian wide characters take two) and break lines where a terminal would, to know whether a
 * table fits or must fall back to its vertical layout. Called by the table layout in `markdown/`.
 */

/** Code point ranges that a terminal draws two columns wide (CJK, full-width forms, emoji). */
const WIDE_RANGES: readonly (readonly [number, number])[] = [
  [0x1100, 0x115f],
  [0x2e80, 0x303e],
  [0x3041, 0x33ff],
  [0x3400, 0x4dbf],
  [0x4e00, 0x9fff],
  [0xa000, 0xa4cf],
  [0xac00, 0xd7a3],
  [0xf900, 0xfaff],
  [0xfe30, 0xfe6f],
  [0xff00, 0xff60],
  [0xffe0, 0xffe6],
  [0x1f300, 0x1f64f],
  [0x1f900, 0x1f9ff],
  [0x20000, 0x3fffd],
]

/**
 * Columns one character takes in a terminal.
 *
 * @param codePoint - The character's code point.
 * @returns 0 for combining and zero-width marks, 2 for wide characters, 1 otherwise.
 */
export function cellWidth(codePoint: number): 0 | 1 | 2 {
  // Combining marks, zero-width joiners and variation selectors add no column
  if (
    (codePoint >= 0x0300 && codePoint <= 0x036f) ||
    (codePoint >= 0x200b && codePoint <= 0x200f) ||
    (codePoint >= 0xfe00 && codePoint <= 0xfe0f)
  ) {
    return 0
  }
  for (const [from, to] of WIDE_RANGES) {
    if (codePoint >= from && codePoint <= to) return 2
  }
  return 1
}

/**
 * Columns a text takes on one line.
 *
 * @param text - A text without line breaks.
 * @returns The sum of its characters' {@link cellWidth}.
 */
export function displayWidth(text: string): number {
  let width = 0
  for (const char of text) width += cellWidth(char.codePointAt(0) ?? 0)
  return width
}

/**
 * Cut a text into rows of at most `width` columns the way the terminal cuts command output: by
 * columns alone, in the middle of a word when the row is full.
 *
 * Why it exists: prose wraps at spaces ({@link wrapLines}), but a command's output is cut at the
 * column where the row ends, and the `… +N lines` under it counts the rows that cut makes. Used by
 * the clamped output of the tool rows.
 *
 * @param text - The output, with its own line breaks.
 * @param width - Columns a row may take.
 * @returns The rows, each without trailing white space.
 *
 * @example
 * hardWrapLines('abcdef', 4) // ['abcd', 'ef']
 */
export function hardWrapLines(text: string, width: number): string[] {
  const limit = Math.max(1, width)
  const rows: string[] = []
  for (const line of text.split('\n')) {
    let row = ''
    let rowWidth = 0
    for (const char of line) {
      const charWidth = cellWidth(char.codePointAt(0) ?? 0)
      // The row is full: the character opens the next one
      if (rowWidth + charWidth > limit) {
        rows.push(row.trimEnd())
        row = ''
        rowWidth = 0
      }
      row += char
      rowWidth += charWidth
    }
    rows.push(row.trimEnd())
  }
  return rows
}

/**
 * Break a text into lines of at most a width, at spaces where it can and inside a word where it must.
 *
 * Why it exists: it is how a terminal wraps a table cell, and the table layout needs the line count to
 * decide between the grid and the vertical layout. Called by `layoutTable`.
 *
 * @param text - The text; its own line breaks are kept.
 * @param width - Columns per line, at least 1.
 * @returns The lines, each at most `width` columns wide.
 */
export function wrapLines(text: string, width: number): string[] {
  const limit = Math.max(1, width)
  const lines: string[] = []
  for (const paragraph of text.split('\n')) {
    let line = ''
    let lineWidth = 0
    for (const word of paragraph.split(/(?<= )/)) {
      const wordWidth = displayWidth(word.trimEnd())
      // The word fits after what the line holds
      if (lineWidth + wordWidth <= limit) {
        line += word
        lineWidth += displayWidth(word)
        continue
      }
      // The word starts a new line when it can fit on one
      if (line !== '') {
        lines.push(line.trimEnd())
        line = ''
        lineWidth = 0
      }
      if (wordWidth <= limit) {
        line = word
        lineWidth = displayWidth(word)
        continue
      }
      // A word longer than the width is hard-wrapped
      for (const char of word.trimEnd()) {
        const charWidth = cellWidth(char.codePointAt(0) ?? 0)
        if (lineWidth + charWidth > limit) {
          lines.push(line)
          line = ''
          lineWidth = 0
        }
        line += char
        lineWidth += charWidth
      }
    }
    lines.push(line.trimEnd())
  }
  return lines
}
