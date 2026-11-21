import type { Token, Tokens } from 'marked'
import { Fragment, type ReactNode } from 'react'

/**
 * Which rules a markdown text is drawn by: a reply uses all of them; a Prompt is drawn in "prompt
 * mode", where links and line-break syntax stay literal (messages.md, section 3.2).
 */
export type MarkdownMode = 'reply' | 'prompt'

/** A token of `marked`, read through the fields every kind may carry. */
export type MarkdownToken = Tokens.Generic

/** Schemes a link may have to be clickable; anything else (`javascript:`) is printed as text. */
const SAFE_LINK_SCHEME = /^(https?:|mailto:)/i

/**
 * Replace the entities the terminal turns into plain text.
 *
 * @param text - Text of a `marked` token.
 * @returns The text with `&nbsp;` as a space.
 */
function plain(text: string): string {
  return text.replaceAll('&nbsp;', ' ')
}

/**
 * The text of tokens with their styling stripped.
 *
 * Why it exists: the table layout measures and wraps cells as plain text, before anything is drawn.
 * Called by the table renderer.
 *
 * @param tokens - Inline tokens of a table cell or a heading.
 * @returns What the tokens would show as characters.
 */
export function plainText(tokens: Token[] | undefined): string {
  let text = ''
  for (const token of (tokens ?? []) as MarkdownToken[]) {
    if (token.type === 'br') text += '\n'
    else if (token.type === 'image')
      text += token['text'] ? `${token['text']} (${token['href']})` : String(token['href'])
    else if (token.tokens) text += plainText(token.tokens)
    else text += plain(String(token['text'] ?? token.raw))
  }
  return text
}

/**
 * Draw inline markdown tokens.
 *
 * Why it exists: a paragraph, a heading, a list item and a table cell all hold inline tokens, and
 * they are all drawn the same way: bold and italic as styles, code in the `permission` colour, links
 * in bright blue. Called by the block renderer and by the table renderer.
 *
 * @param tokens - Inline tokens from `marked`.
 * @param mode - The rule set; prompt mode leaves links and line breaks literal.
 * @returns React nodes, one per token.
 */
export function renderInline(tokens: Token[] | undefined, mode: MarkdownMode): ReactNode[] {
  return ((tokens ?? []) as MarkdownToken[]).map((token, index) => (
    <Fragment key={index}>{inlineNode(token, mode)}</Fragment>
  ))
}

/** One inline token as a React node. */
function inlineNode(token: MarkdownToken, mode: MarkdownMode): ReactNode {
  switch (token.type) {
    case 'text':
    case 'escape':
      return token.tokens ? renderInline(token.tokens, mode) : plain(String(token['text']))
    case 'strong':
      return <strong className="md-strong">{renderInline(token.tokens, mode)}</strong>
    case 'em':
      return <em>{renderInline(token.tokens, mode)}</em>
    case 'del':
      // The Mirror always draws a strikethrough: it is a web page, not a terminal that may lack one
      return <del>{renderInline(token.tokens, mode)}</del>
    case 'codespan':
      return codeSpan(String(token['text']))
    case 'br':
      // Prompt mode keeps the line-break syntax as typed
      return mode === 'prompt' ? token.raw : '\n'
    case 'link':
      return mode === 'prompt' ? token.raw : link(token, mode)
    case 'image':
      return token['text'] ? `${token['text']} (${token['href']})` : String(token['href'])
    case 'checkbox':
      return token['checked'] ? '[x] ' : '[ ] '
    default:
      // Inline HTML and anything unknown is printed as written
      return token.raw
  }
}

/** Inline code: the `permission` colour, and a hyperlink when the code is a bare web address. */
function codeSpan(text: string): ReactNode {
  if (/^https?:\/\/\S+$/.test(text)) {
    return (
      <a className="md-code" href={text} title={text} target="_blank" rel="noreferrer noopener">
        {text}
      </a>
    )
  }
  return <code className="md-code">{text}</code>
}

/** A link: bright-blue text that carries the address; autolinks and bare URLs are printed as written. */
function link(token: MarkdownToken, mode: MarkdownMode): ReactNode {
  const href = String(token['href'])
  const text = String(token['text'])
  // `<url>` and bare URLs are printed as written, uncoloured
  if (!token.raw.startsWith('[')) return text
  // A mail link prints the address only
  if (href.toLowerCase().startsWith('mailto:')) return href.slice('mailto:'.length)
  // An address with no safe scheme is shown, never made clickable
  if (!SAFE_LINK_SCHEME.test(href)) return `${text} (${href})`
  return (
    <a className="md-link" href={href} title={href} target="_blank" rel="noreferrer noopener">
      {renderInline(token.tokens, mode)}
    </a>
  )
}
