import { marked } from 'marked'
import { useMemo, type ReactNode } from 'react'

import { renderBlocks } from './blocks'
import type { MarkdownMode } from './inline'

/**
 * Turn markdown text into tokens, with the one fix the terminal makes first.
 *
 * Why it exists: Claude Code escapes a pipe inside inline code before parsing, so `a|b` in a table cell
 * does not split the cell. Called by {@link Markdown} when its text changes.
 *
 * @param source - Markdown as the model wrote it.
 * @returns The block tokens of `marked`'s GFM lexer.
 */
export function lexMarkdown(source: string) {
  const escaped = source
    .split('\n')
    .map((line) =>
      // Only lines that can be table rows, and only inside backticks
      line.includes('|') ? line.replace(/`[^`\n]*`/g, (span) => span.replaceAll(/(?<!\\)\|/g, '\\|')) : line,
    )
    .join('\n')
  return marked.lexer(escaped, { gfm: true })
}

/**
 * The markdown renderer: `marked` tokenizes, this draws the tokens as the terminal draws them.
 *
 * Why it exists: replies, slash-command output and Prompts are markdown, and the terminal's own
 * look (headings by weight, `-` bullets, a `▎` quote bar, box-drawing tables, coloured fences) is
 * not what a browser gives for the same tokens. Used by {@link ReplyRow}, {@link CommandOutputRow}
 * and {@link PromptRow}, and by later rows that show markdown.
 *
 * @param props.source - The markdown text.
 * @param props.mode - `reply` (default) or `prompt`, which leaves tables, quotes, rules and links literal.
 * @param props.tail - Content for the end of the last line (the dim ` · summary` tag).
 */
export function Markdown({
  source,
  mode = 'reply',
  tail,
}: {
  source: string
  mode?: MarkdownMode
  tail?: ReactNode
}) {
  const tokens = useMemo(() => lexMarkdown(source), [source])
  return <div className="md">{renderBlocks(tokens, { mode, depth: 0 }, tail)}</div>
}
