/**
 * Escape a text for HTML content or a double-quoted attribute value.
 *
 * @param text - A title, a section name or a page number written into the Handout's markup.
 * @returns The text with `&`, `<`, `>` and `"` as character references.
 *
 * @example
 * escapeHtml('A & <B>')    // 'A &amp; &lt;B&gt;'
 * escapeHtml('say "hi"')   // 'say &quot;hi&quot;'
 */
export function escapeHtml(text: string): string {
  return text.replace(/[&<>"]/g, (character) => `&#${character.charCodeAt(0)};`)
}
