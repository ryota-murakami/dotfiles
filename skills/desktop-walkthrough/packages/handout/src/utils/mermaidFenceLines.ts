/**
 * Lines of the Handout's diagrams in a page's original source: the opening fence of each ```mermaid
 * block that is not inside a `<!-- hud-only -->` block, in reading order.
 *
 * Why it exists: page.html numbers diagrams in the filtered source it renders, and a message must
 * point at the original file. Fences follow the same rules as dw's marker filter: ``` or ~~~, closed
 * by the same character at least as long; a line indented 4 or more spaces is never a fence.
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
  let fence: { character: string; length: number } | null = null
  let hudOnly = false
  markdown.split('\n').forEach((text, index) => {
    const opening = /^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)/.exec(text)
    // Inside a fence only its closing line matters
    if (fence) {
      const closing = /^ {0,3}(`{3,}|~{3,})\s*$/.exec(text)
      if (closing?.[1] && closing[1][0] === fence.character && closing[1].length >= fence.length) fence = null
      return
    }
    if (opening?.[1]) {
      fence = { character: opening[1].charAt(0), length: opening[1].length }
      if (opening[2] === 'mermaid' && !hudOnly) lines.push(index + 1)
      return
    }
    if (/^ {0,3}<!-- hud-only -->\s*$/.test(text)) hudOnly = true
    else if (/^ {0,3}<!-- \/hud-only -->\s*$/.test(text)) hudOnly = false
  })
  return lines
}
