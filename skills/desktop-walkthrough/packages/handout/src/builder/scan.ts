import { findSecrets } from '../../../../hooks/secrets'
import type { Diagnostic, HandoutPage } from '../contract'
import { collectReadableText } from '../utils/collectReadableText'

/**
 * Find every secret shape in what the Handout would carry, before anything is rendered (DX D8).
 *
 * Why it exists: a Handout leaves the machine. A signed link behind harmless link text or a key in
 * a diagram source would reach a colleague's inbox, so the export stops and names where each one is.
 * Reads the page sources (link targets and diagram sources included), titles and section names.
 * A page is named by its number, never its file name: dw makes that from the title, where a value
 * the scan found would read again. Called first by {@link buildHandout}.
 *
 * @param pages - The Record's pages as dw listed them.
 * @returns One HANDOUT_SECRET per finding, with page, line and shape name; empty when nothing was found.
 *
 * @example
 * scanForSecrets([{ n: 2, markdown: '…?signature=0f3a…\n', title: '設定', section: '', built: 'pages/002.html' }])
 * // [{ code: 'HANDOUT_SECRET', page: 2, line: 1, pattern: 'signed-url-parameter',
 * //    message: 'page 2:1: a secret shape (signed-url-parameter); remove the value from the page' }]
 */
export function scanForSecrets(pages: readonly HandoutPage[]): Diagnostic[] {
  const diagnostics: Diagnostic[] = []
  for (const page of pages) {
    const sourceFindings = findSecrets(page.markdown)
    for (const finding of sourceFindings) {
      diagnostics.push({
        code: 'HANDOUT_SECRET',
        message: `page ${page.n}:${finding.line}: a secret shape (${finding.pattern}); remove the value from the page`,
        page: page.n,
        line: finding.line,
        pattern: finding.pattern,
      })
    }
    // Every title is checked on its own: inside a longer word of the page a value escapes the page's
    // scan and still stands alone in the header and the table of contents. A title that is the page's
    // heading was reported at that line above
    const headingIndex = page.markdown
      .split('\n')
      .findIndex((line) => line.replace(/^# +/, '').trim() === page.title)
    const reportedAtHeading =
      headingIndex >= 0 && sourceFindings.some((finding) => finding.line === headingIndex + 1)
    if (!reportedAtHeading) {
      for (const finding of findSecrets(page.title)) {
        diagnostics.push({
          code: 'HANDOUT_SECRET',
          message: `page ${page.n}: a secret shape (${finding.pattern}) in its title; give the page another title`,
          page: page.n,
          pattern: finding.pattern,
        })
      }
    }
    for (const finding of findSecrets(page.section)) {
      diagnostics.push({
        code: 'HANDOUT_SECRET',
        message: `page ${page.n}: a secret shape (${finding.pattern}) in its section name (pages/sections.tsv)`,
        page: page.n,
        pattern: finding.pattern,
      })
    }
  }
  return diagnostics
}

/**
 * Find every secret shape in a page as the colleague receives it: its sanitized HTML, text and
 * attribute values decoded.
 *
 * Why it exists: {@link scanForSecrets} reads the source as written, where a value can hide behind
 * HTML's own escapes: `&amp;signature=` in a pasted link reads as a working `&signature=` once parsed.
 * Called by {@link buildHandout} for every page after sanitizing, before the pages are assembled.
 * Only the sources of embedded pictures are skipped (an `<img>`'s `src`, an SVG `<image>`'s `href`):
 * {@link embedImages} checked their bytes. Every other value is read, one starting with `data:` too.
 *
 * @param page - The page the content belongs to (its number names it in the message).
 * @param html - The page's content as it goes into the Handout.
 * @returns One HANDOUT_SECRET per finding, with page and shape name; empty when nothing was found.
 *
 * @example
 * scanRenderedPage(page, '<a href="https://docs.test/a?expires=1&amp;signature=0f3a…">設計メモ</a>')
 * // [{ code: 'HANDOUT_SECRET', page: 2, pattern: 'signed-url-parameter',
 * //    message: 'page 2: a secret shape (signed-url-parameter) in the page as rendered (…); remove the value from the page' }]
 */
export function scanRenderedPage(page: HandoutPage, html: string): Diagnostic[] {
  const holder = document.createElement('template')
  holder.innerHTML = html
  return findSecrets(collectReadableText(holder.content, isEmbeddedPicture)).map((finding): Diagnostic => ({
    code: 'HANDOUT_SECRET',
    message: `page ${page.n}: a secret shape (${finding.pattern}) in the page as rendered (the source spells it with HTML entities or escapes); remove the value from the page`,
    page: page.n,
    pattern: finding.pattern,
  }))
}

/**
 * Whether an attribute is the source of a picture {@link embedImages} embedded, whose bytes it checked
 * (the base64 of a picture is no text to read): an `<img>`'s `src`, an SVG `<image>`'s `href` or
 * `xlink:href`, holding `data:image/…`. Any other value starting with `data:` is read like all text.
 *
 * @param element - The element holding the attribute.
 * @param attribute - The attribute.
 * @returns Whether the rendered-page scan skips its value.
 *
 * @example
 * isEmbeddedPicture(img, img.getAttributeNode('src'))    // true for <img src="data:image/png;base64,…">
 * isEmbeddedPicture(span, span.getAttributeNode('title')) // false for <span title="data:,…">
 */
function isEmbeddedPicture(element: Element, attribute: Attr): boolean {
  if (!/^data:image\//i.test(attribute.value)) return false
  if (element.localName === 'img') return attribute.name === 'src'
  return (
    element.localName === 'image' &&
    element.closest('svg') !== null &&
    (attribute.name === 'href' || attribute.name === 'xlink:href')
  )
}
