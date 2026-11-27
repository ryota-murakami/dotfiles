/**
 * Every text a parsed page or drawing carries for a reader: its text content, then each attribute
 * value, one per line, with HTML and XML escapes decoded.
 *
 * Why it exists: a secret can hide behind the escapes of HTML or XML (`&amp;signature=`, `&#65;KIA…`)
 * and read in the clear once a browser parses it. The secret scans read what the parser made of the
 * text, not the text as written. Called by {@link scanRenderedPage} for a page as rendered, and by
 * the image check of {@link embedImages} for an SVG's document.
 *
 * @param root - A parsed page (a template's content) or an SVG document from `DOMParser`.
 * @param isSkipped - Whether an attribute's value is no text to read (an embedded picture, checked as bytes).
 * @returns The text content, then every attribute value not skipped, one per line.
 *
 * @example
 * const parsed = new DOMParser().parseFromString('<svg xmlns="http://www.w3.org/2000/svg"><a href="x?a=1&amp;b=2"><text>&#65;B</text></a></svg>', 'image/svg+xml')
 * collectReadableText(parsed) // 'AB\nhttp://www.w3.org/2000/svg\nx?a=1&b=2'
 */
export function collectReadableText(
  root: Document | DocumentFragment,
  isSkipped: (element: Element, attribute: Attr) => boolean = () => false,
): string {
  // A document's own textContent is null: its text is its root element's
  const texts = [('documentElement' in root ? root.documentElement?.textContent : root.textContent) ?? '']
  for (const element of Array.from(root.querySelectorAll('*'))) {
    for (const attribute of Array.from(element.attributes)) {
      if (!isSkipped(element, attribute)) texts.push(attribute.value)
    }
  }
  return texts.join('\n')
}
