/**
 * An opening fence: the list markers it may follow on its line (`- `, `1. `, nested `1. - `), up to 3
 * spaces, the run of ``` or ~~~, and the rest of the line. The same rule as dw's explain_filter.
 */
const FENCE_OPENING = /^((?: {0,3}(?:[-*+]|\d{1,9}[.)])[ \t]+)*) {0,3}(`{3,}|~{3,})(.*)$/

/**
 * Lines of the Handout's diagrams in a page's original source: the opening fence of each ```mermaid
 * block that is not inside a `<!-- hud-only -->` block, in reading order.
 *
 * Why it exists: page.html numbers diagrams in the filtered source it renders, and a message must
 * point at the original file. Fences follow the same rules as dw's marker filter: ``` or ~~~, also
 * on a list item's line (`- ````), closed by the same character at least as long, indented at most 3
 * spaces past the list item; a line indented 4 or more spaces is never a fence, and a backtick fence
 * with a backtick after it on its line (```x```) is code inside the text.
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
  let fence: { character: string; length: number; indent: number } | null = null
  let hudOnly = false
  markdown.split('\n').forEach((line, index) => {
    // A page saved with Windows line endings: its fences and markers end in a carriage return
    const text = line.replace(/\r$/, '')
    // Inside a fence only its closing line matters: indented at most 3 past the list item it opened in
    if (fence) {
      const closing = /^([ \t]*)(`{3,}|~{3,})[ \t]*$/.exec(text)
      if (
        closing?.[1] !== undefined &&
        closing[2] !== undefined &&
        closing[1].length <= fence.indent + 3 &&
        closing[2].charAt(0) === fence.character &&
        closing[2].length >= fence.length
      )
        fence = null
      return
    }
    const opening = FENCE_OPENING.exec(text)
    const run = opening?.[2] ?? ''
    const rest = opening?.[3] ?? ''
    // "```x```" at the start of a line is code inside the text, not a fence
    if (opening && !(run.startsWith('`') && rest.includes('`'))) {
      fence = { character: run.charAt(0), length: run.length, indent: (opening[1] ?? '').length }
      if (/^\s*mermaid(?:\s|$)/.test(rest) && !hudOnly) lines.push(index + 1)
      return
    }
    if (/^ {0,3}<!-- hud-only -->\s*$/.test(text)) hudOnly = true
    else if (/^ {0,3}<!-- \/hud-only -->\s*$/.test(text)) hudOnly = false
  })
  return lines
}
