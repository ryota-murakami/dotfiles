import { MESSAGE_EXCERPT_CHARS } from '../constants'

/**
 * Shorten a quoted text for a one-line message: whitespace runs become one space, a long text is cut.
 *
 * @param text - A diagram label, an error text or a file name a message quotes.
 * @returns The text on one line, at most {@link MESSAGE_EXCERPT_CHARS} characters plus `…`.
 *
 * @example
 * excerpt('利用者が\n  書き出しを押す') // '利用者が 書き出しを押す'
 * excerpt('x'.repeat(100))              // 'xxxx…' (60 characters, then `…`)
 */
export function excerpt(text: string): string {
  const oneLine = text.replace(/\s+/g, ' ').trim()
  return oneLine.length > MESSAGE_EXCERPT_CHARS ? `${oneLine.slice(0, MESSAGE_EXCERPT_CHARS)}…` : oneLine
}
