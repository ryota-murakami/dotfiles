import { MESSAGE_EXCERPT_CHARS } from '../constants'

/**
 * Shorten a quoted text for a one-line message: whitespace runs become one space, a long text is cut.
 *
 * @param text - A diagram label, an error text or an image source a message quotes.
 * @returns The text on one line, at most {@link MESSAGE_EXCERPT_CHARS} characters (code points, so
 * an emoji is never cut in half) plus `…`.
 *
 * @example
 * excerpt('利用者が\n  書き出しを押す') // '利用者が 書き出しを押す'
 * excerpt('x'.repeat(100))              // 'xxxx…' (60 characters, then `…`)
 */
export function excerpt(text: string): string {
  const oneLine = text.replace(/\s+/g, ' ').trim()
  // Counted and cut by characters, not UTF-16 units: an emoji at the cut stays whole
  const characters = Array.from(oneLine)
  return characters.length > MESSAGE_EXCERPT_CHARS
    ? `${characters.slice(0, MESSAGE_EXCERPT_CHARS).join('')}…`
    : oneLine
}
