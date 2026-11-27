import { MARKDOWN_TAB_STOP_COLUMNS } from '../constants'

/** One quote or list marker an opening fence may follow on its line: `> `, `- `, `1. `. */
const LINE_MARKER = /^ {0,3}(?:> ?|(?:[-*+]|\d{1,9}[.)])[ \t]+)/

/** A fence's run of ``` or ~~~ after up to 3 spaces, and the rest of its line. */
const FENCE_RUN = /^ {0,3}(`{3,}|~{3,})(.*)$/

/**
 * Read an opening fence: the quote and list markers it follows on its line (`> `, `- `, `1. `, nested
 * `1. - `), up to 3 spaces, the run of ``` or ~~~, and the rest of the line. The markers are read one
 * at a time, each once: a long run of them that opens no fence costs one pass, never a try of every
 * way to split it. The same rule as dw's explain_filter.
 *
 * @param text - One line of a page.
 * @returns The markers before the fence, its run and the rest of the line; null for a line that opens none.
 *
 * @example
 * fenceOpening('- ```bash') // { prefix: '- ', run: '```', rest: 'bash' }
 * fenceOpening('> > text')  // null
 */
function fenceOpening(text: string): { prefix: string; run: string; rest: string } | null {
  let markersEnd = 0
  for (let marker = LINE_MARKER.exec(text); marker; marker = LINE_MARKER.exec(text.slice(markersEnd))) {
    markersEnd += marker[0].length
  }
  const fence = FENCE_RUN.exec(text.slice(markersEnd))
  return fence ? { prefix: text.slice(0, markersEnd), run: fence[1] ?? '', rest: fence[2] ?? '' } : null
}

/** The quote markers at the start of a line (`> > `). */
const QUOTE_MARKERS = /^(?: {0,3}> ?)+/

/**
 * The columns a line's indentation takes: a tab reaches the next tab stop, a space or a marker
 * character takes one.
 *
 * @example
 * columns('  ') // 2
 * columns('\t')  // 4
 */
function columns(indentation: string): number {
  let width = 0
  for (const character of indentation) {
    width =
      character === '\t' ? width + MARKDOWN_TAB_STOP_COLUMNS - (width % MARKDOWN_TAB_STOP_COLUMNS) : width + 1
  }
  return width
}

/**
 * How many quote markers start a line.
 *
 * @example
 * quoteDepth('> > text') // 2
 * quoteDepth('text')     // 0
 */
function quoteDepth(text: string): number {
  return (QUOTE_MARKERS.exec(text)?.[0].match(/>/g) ?? []).length
}

/**
 * A line without its first COUNT quote markers.
 *
 * @example
 * withoutQuotes('> > ```', 2) // '```'
 */
function withoutQuotes(text: string, count: number): string {
  let rest = text
  for (let removed = 0; removed < count; removed++) rest = rest.replace(/^ {0,3}> ?/, '')
  return rest
}

/**
 * Lines of the Handout's diagrams in a page's original source: the opening fence of each ```mermaid
 * block that is not inside a `<!-- hud-only -->` block, in reading order.
 *
 * Why it exists: page.html numbers diagrams in the filtered source it renders, and a message must
 * point at the original file. Fences follow the same rules as dw's marker filter: ``` or ~~~, also
 * on a list item's line (`- ````) or in a quote (`> ````), closed by the same character at least as
 * long, indented at most 3 columns past the list item (a tab counts to its tab stop; quoted as deep
 * in a quote), and ending where its quote or list item ends; a line indented 4 or more spaces is
 * never a fence, and a backtick fence with a backtick after it on its line (```x```)
 * is code inside the text.
 *
 * @param markdown - A page's original source (both audiences).
 * @returns 1-based line numbers; index K-1 is the line of diagram K.
 *
 * @example
 * mermaidFenceLines('# A\n```mermaid\nflowchart LR\n```\n') // [2]
 * mermaidFenceLines('<!-- hud-only -->\n```mermaid\nx\n```\n<!-- /hud-only -->\n') // []
 */
export function mermaidFenceLines(markdown: string): number[] {
  const lines: number[] = []
  let fence: { character: string; length: number; indent: number; quotes: number } | null = null
  let hudOnly = false
  markdown.split('\n').forEach((line, index) => {
    // A page saved with Windows line endings: its fences and markers end in a carriage return
    const text = line.replace(/\r$/, '')
    // A fence ends where its container does: a quote at a line with fewer quote markers, a list item
    // at a line (not blank) indented less than its text; the line is then read like any other
    if (fence && fence.quotes > 0 && quoteDepth(text) < fence.quotes) fence = null
    if (
      fence &&
      fence.quotes === 0 &&
      fence.indent > 0 &&
      text.trim() !== '' &&
      columns(/^[ \t]*/.exec(text)?.[0] ?? '') < fence.indent
    )
      fence = null
    // Inside a fence only its closing line matters: indented at most 3 columns past the list item it
    // opened in (a tab counts to its tab stop), quoted as deep as it opened
    if (fence) {
      const closing = /^([ \t]*)(`{3,}|~{3,})[ \t]*$/.exec(withoutQuotes(text, fence.quotes))
      if (
        closing?.[1] !== undefined &&
        closing[2] !== undefined &&
        columns(closing[1]) <= fence.indent + 3 &&
        closing[2].charAt(0) === fence.character &&
        closing[2].length >= fence.length
      )
        fence = null
      return
    }
    const opening = fenceOpening(text)
    const run = opening?.run ?? ''
    const rest = opening?.rest ?? ''
    // "```x```" at the start of a line is code inside the text, not a fence
    if (opening && !(run.startsWith('`') && rest.includes('`'))) {
      const prefix = opening.prefix
      const quotes = (prefix.match(/>/g) ?? []).length
      fence = {
        character: run.charAt(0),
        length: run.length,
        indent: columns(quotes > 0 ? prefix.replace(QUOTE_MARKERS, '') : prefix),
        quotes,
      }
      if (/^\s*mermaid(?:\s|$)/.test(rest) && !hudOnly) lines.push(index + 1)
      return
    }
    if (/^ {0,3}<!-- hud-only -->\s*$/.test(text)) hudOnly = true
    else if (/^ {0,3}<!-- \/hud-only -->\s*$/.test(text)) hudOnly = false
  })
  return lines
}
