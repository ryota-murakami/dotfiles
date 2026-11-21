import type { Token, Tokens } from 'marked'
import { Fragment, type ReactNode } from 'react'

import { useColumns } from '../terminal/columns'
import { highlightCode, isKnownLanguage } from './highlight'
import { renderInline, type MarkdownMode, type MarkdownToken } from './inline'
import { listMarker } from './listMarkers'
import { TableBlock } from './Table'

/** What a block needs to know about where it is drawn. */
export type BlockContext = {
  mode: MarkdownMode
  /** How many lists the block is nested in. */
  depth: number
}

/** Block kinds that always have a blank row before them. */
const GAP_BEFORE = new Set(['table', 'blockquote', 'hr'])
/** Block kinds that always have a blank row after them, when something follows. */
const GAP_AFTER = new Set(['table', 'blockquote', 'hr', 'heading'])
/** Block kinds whose last line a trailing tag may join. */
const INLINE_BLOCKS = new Set(['paragraph', 'text', 'heading'])

/**
 * Draw block-level markdown tokens, with the blank rows the terminal puts between them.
 *
 * Why it exists: the terminal keeps one blank row where the source had a blank line, and always puts
 * one around tables, quotes, rules and after headings, while a tight list or a fence right under a
 * paragraph gets none. This is that rule, plus one dispatch per block kind. Called by {@link Markdown}
 * and, for the content of quotes and list items, by itself.
 *
 * @param tokens - Block tokens from `marked`.
 * @param context - Mode and nesting.
 * @param tail - Text to put after the last line of the last block, when that block is a paragraph or a heading (the dim ` · summary`); otherwise it goes on a line of its own.
 * @returns The blocks, separated.
 */
export function renderBlocks(tokens: Token[], context: BlockContext, tail?: ReactNode): ReactNode {
  const blocks: { token: MarkdownToken; hasGap: boolean }[] = []
  let sawBlank = false
  for (const token of tokens as MarkdownToken[]) {
    // A blank line in the source is kept as one blank row; link definitions draw nothing
    if (token.type === 'space') {
      sawBlank = true
      continue
    }
    if (token.type === 'def') continue
    const previous = blocks.at(-1)
    const hasGap =
      previous !== undefined && (sawBlank || GAP_BEFORE.has(token.type) || GAP_AFTER.has(previous.token.type))
    blocks.push({ token, hasGap })
    sawBlank = false
  }

  const lastIndex = blocks.length - 1
  const lastKind = blocks.at(-1)?.token.type
  const tailJoinsLast = tail !== undefined && lastKind !== undefined && INLINE_BLOCKS.has(lastKind)
  return (
    <>
      {blocks.map(({ token, hasGap }, index) => (
        <div key={index} className={hasGap ? 'md-gap' : undefined}>
          {block(token, context, index === lastIndex && tailJoinsLast ? tail : undefined)}
        </div>
      ))}
      {tail !== undefined && !tailJoinsLast ? <div>{tail}</div> : null}
    </>
  )
}

/** One block token as a React node. */
function block(token: MarkdownToken, context: BlockContext, tail: ReactNode): ReactNode {
  const { mode } = context
  switch (token.type) {
    case 'paragraph':
    case 'text':
      return (
        <p className="md-p">
          {renderInline(token.tokens ?? [{ type: 'text', raw: token.raw, text: token['text'] }], mode)}
          {tail}
        </p>
      )
    case 'heading':
      // Prompt mode leaves underline-style headings literal
      if (mode === 'prompt' && !token.raw.startsWith('#'))
        return <p className="md-p">{token.raw.trimEnd()}</p>
      return (
        <div className={token['depth'] === 1 ? 'md-h md-h1' : 'md-h'}>
          {renderInline(token.tokens, mode)}
          {tail}
        </div>
      )
    case 'code':
      return <CodeBlock token={token as Tokens.Code} />
    case 'blockquote':
      // Prompt mode keeps quotes literal
      if (mode === 'prompt') return <p className="md-p">{token.raw.trimEnd()}</p>
      return <div className="md-quote">{renderBlocks(token.tokens ?? [], context)}</div>
    case 'hr':
      // The terminal prints the three characters, not a drawn rule
      return <div>---</div>
    case 'list':
      return <ListBlock token={token as Tokens.List} context={context} />
    case 'table':
      if (mode === 'prompt') return <p className="md-p">{token.raw.trimEnd()}</p>
      return <TableBlock token={token as Tokens.Table} mode={mode} />
    default:
      // Block HTML and anything unknown is printed as written
      return <p className="md-p">{token.raw.trimEnd()}</p>
  }
}

/** A fenced or indented code block: coloured when its language is known, otherwise plain under a dim label. */
function CodeBlock({ token }: { token: Tokens.Code }) {
  const language = (token.lang ?? '').trim().split(/\s+/)[0] ?? ''
  const isIndented = token.codeBlockStyle === 'indented'
  // Indented code is plain, unstyled text
  if (isIndented) return <pre className="md-fence">{token.text}</pre>
  // No language: the whole fence in the `permission` colour
  if (language === '') return <pre className="md-fence md-fence-plain">{token.text}</pre>
  if (isKnownLanguage(language)) {
    return (
      <pre className="md-fence">
        <code dangerouslySetInnerHTML={{ __html: highlightCode(token.text, language) }} />
      </pre>
    )
  }
  // A language the highlighter does not know: its label on a dim line, then the plain code
  return (
    <>
      <div className="dim dim-markdown">{language}</div>
      <pre className="md-fence">{token.text}</pre>
    </>
  )
}

/** A list: one marker cell per item, wide enough for the widest marker plus a space. */
function ListBlock({ token, context }: { token: Tokens.List; context: BlockContext }) {
  const columns = useColumns()
  const start = typeof token.start === 'number' ? token.start : 1
  const markers = token.items.map((_, index) => listMarker(token.ordered, start + index, context.depth))
  // The marker cell is at least two columns, and a nested list indents by it
  const cell = Math.max(2, ...markers.map((marker) => marker.length + 1))
  // Top-level lists wrap in a narrower room than prose
  const style = context.depth === 0 ? { maxWidth: `${Math.max(10, columns - 14)}ch` } : undefined

  return (
    <div className="md-list" style={style}>
      {token.items.map((item, index) => {
        const previous = token.items[index - 1]
        // A blank row between items only when the previous one ended with a blank line, a heading or a table
        const hasGap = previous !== undefined && endsLoosely(previous)
        return (
          <Fragment key={index}>
            <div className={hasGap ? 'md-item md-gap' : 'md-item'}>
              <span className="md-marker" style={{ width: `${cell}ch` }}>
                {markers[index]}
              </span>
              <div className="md-item-body">
                {renderBlocks(withTaskPrefix(item), { ...context, depth: context.depth + 1 })}
              </div>
            </div>
          </Fragment>
        )
      })}
    </div>
  )
}

/** Whether a list item ends with a blank line, a heading or a table. */
function endsLoosely(item: Tokens.ListItem): boolean {
  if (/\n[ \t]*\n$/.test(item.raw)) return true
  const last = item.tokens.toReversed().find((token) => token.type !== 'space')
  return last?.type === 'heading' || last?.type === 'table'
}

/** The item's tokens; a task item's checkbox becomes `[ ] ` or `[x] ` at the start of its first text. */
function withTaskPrefix(item: Tokens.ListItem): Token[] {
  const [first, ...rest] = item.tokens as MarkdownToken[]
  if (first?.type !== 'checkbox') return item.tokens
  const box: MarkdownToken = first
  const [text, ...others] = rest
  if (text && (text.type === 'text' || text.type === 'paragraph')) {
    return [{ ...text, tokens: [box, ...(text.tokens ?? [])] }, ...others]
  }
  // A task item that starts with something else shows its box on a line of its own
  return [{ type: 'paragraph', raw: '', tokens: [box] }, ...rest]
}
