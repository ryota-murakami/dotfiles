/**
 * Escape a text for HTML content or a double-quoted attribute value.
 *
 * @param text - A title, a section name or a page number written into the Handout's markup.
 * @returns The text with `&`, `<`, `>` and `"` as numeric character references.
 *
 * @example
 * escapeHtml('A & <B>')    // 'A &#38; &#60;B&#62;'
 * escapeHtml('say "hi"')   // 'say &#34;hi&#34;'
 */
export function escapeHtml(text: string): string {
  return text.replace(/[&<>"]/g, (character) => `&#${character.charCodeAt(0)};`)
}
