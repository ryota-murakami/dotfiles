/**
 * Every text a parsed page or drawing carries for a reader, with HTML and XML escapes decoded: its
 * text as one run (a key split across spans reads whole), each text node on its own line (a line
 * break or a new block is a boundary the reader sees, so `note<br>&#65;KIA…` does not read as one
 * word), then each attribute value, one per line. A `<template>`'s contents are read too: they ship
 * in the file, though no browser shows them.
 *
 * Why it exists: a secret can hide behind the escapes of HTML or XML (`&amp;signature=`, `&#65;KIA…`)
 * and read in the clear once a browser parses it. The secret scans read what the parser made of the
 * text, not the text as written. Called by {@link scanRenderedPage} for a page as rendered, and by
 * the image check of {@link embedImages} for an SVG's document.
 *
 * @param root - A parsed page (a template's content) or an SVG document from `DOMParser`.
 * @param isSkipped - Whether an attribute's value is no text to read (an embedded picture, checked as bytes).
 * @returns The texts, one per line.
 *
 * @example
 * const parsed = new DOMParser().parseFromString('<svg xmlns="http://www.w3.org/2000/svg"><a href="x?a=1&amp;b=2"><text>&#65;B</text></a></svg>', 'image/svg+xml')
 * collectReadableText(parsed) // 'AB\nAB\nhttp://www.w3.org/2000/svg\nx?a=1&b=2'
 */
export function collectReadableText(
  root: Document | DocumentFragment,
  isSkipped: (element: Element, attribute: Attr) => boolean = () => false,
): string {
  const texts: string[] = []
  const pending: Array<Document | DocumentFragment> = [root]
  for (let parsed = pending.pop(); parsed; parsed = pending.pop()) {
    // A document's own textContent is null: its text is its root element's
    texts.push(('documentElement' in parsed ? parsed.documentElement?.textContent : parsed.textContent) ?? '')
    const walker = (parsed.ownerDocument ?? parsed).createTreeWalker(parsed, NodeFilter.SHOW_TEXT)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) texts.push(node.textContent ?? '')
    for (const element of Array.from(parsed.querySelectorAll('*'))) {
      for (const attribute of Array.from(element.attributes)) {
        if (!isSkipped(element, attribute)) texts.push(attribute.value)
      }
      // A template's contents live in a fragment of their own, out of reach of the walk above
      if (element instanceof HTMLTemplateElement) pending.push(element.content)
    }
  }
  return texts.join('\n')
}
