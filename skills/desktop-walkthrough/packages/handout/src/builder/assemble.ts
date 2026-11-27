import { HANDOUT_MARKER_META } from '../contract'
import type { TocEntry } from '../dom'
import { HANDOUT_DOM } from '../dom'
import { escapeHtml } from '../utils/escapeHtml'

/** One page ready for the Handout: sanitized content, images embedded. */
export interface AssembledPage extends TocEntry {
  html: string
}

/** Everything a Handout is made of. */
export interface AssembleParts {
  pages: readonly AssembledPage[]
  /** page.html's CSS without the reading marks. */
  pageCss: string
  /** The highlight.js theme the Explainer uses. */
  highlightCss: string
  /** The Handout's own CSS: panel, header, table of contents, pager, print. */
  handoutCss: string
  /** The controller script and the base64 SHA-256 the CSP allows it by. */
  controller: { source: string; sha256: string }
}

/**
 * The Handout's Content-Security-Policy: nothing loads from anywhere, and the only script that may
 * run is the controller, by its hash (DX D14). Styles stay inline (mermaid's SVG carries them);
 * images are embedded `data:` URIs.
 *
 * @param controllerSha256 - Base64 SHA-256 of the controller's source.
 * @returns The policy's text.
 *
 * @example
 * handoutCsp('abc=') // "default-src 'none'; script-src 'sha256-abc='; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'"
 */
export function handoutCsp(controllerSha256: string): string {
  return [
    "default-src 'none'",
    `script-src 'sha256-${controllerSha256}'`,
    "style-src 'unsafe-inline'",
    'img-src data:',
    'font-src data:',
    "base-uri 'none'",
    "form-action 'none'",
  ].join('; ')
}

/**
 * Write the Handout: one HTML file holding every page, the Explainer's look and the controller.
 *
 * Why it exists: the colleague gets one file that opens anywhere, offline. The pages are plain
 * articles in reading order, so without the controller (a mail client's preview) every page still
 * reads top to bottom; the controller turns them into the Explainer's paged panel. The Handout
 * marker comes first in the head, where dw and the host look for it before replacing a file.
 * Called by {@link buildHandout} once every page is checked and sanitized.
 *
 * @param parts - The pages and the styles and script around them.
 * @returns The whole file.
 * @throws When the controller's source contains `</script`, which would cut it short.
 *
 * @example
 * assembleHandout({ pages: [{ n: 1, title: '書き出しの流れ', section: '準備', html: '<h1>書き出しの流れ</h1>' }], … })
 * // '<!doctype html>\n<html lang="ja">\n<head>\n<meta charset="utf-8">\n<meta name="dw-handout" content="1">…'
 */
export function assembleHandout(parts: AssembleParts): string {
  // The controller is inlined as it is: a "</script" in it would end the element and void its hash
  if (/<\/script/i.test(parts.controller.source)) throw new Error('the controller source contains "</script"')
  const title = parts.pages[0]?.title ?? ''
  const toc: TocEntry[] = parts.pages.map(({ n, title: pageTitle, section }) => ({
    n,
    title: pageTitle,
    section,
  }))
  // Ids, `#N` and the header count positions 1..M: a Record whose numbers have gaps still pages 1, 2, 3
  const articles = parts.pages.map(
    (page, index) =>
      `<article class="${HANDOUT_DOM.pageClass}" id="${HANDOUT_DOM.pageIdPrefix}${index + 1}" data-n="${page.n}">` +
      `<div class="${HANDOUT_DOM.sectionClass}">${escapeHtml(page.section)}</div>\n${page.html}\n</article>`,
  )
  // JSON inside a <script> element: "<" is escaped so no text can end the element early
  const tocJson = JSON.stringify(toc).replace(/</g, '\\u003c')
  return [
    '<!doctype html>',
    '<html lang="ja">',
    '<head>',
    '<meta charset="utf-8">',
    HANDOUT_MARKER_META,
    `<meta http-equiv="Content-Security-Policy" content="${handoutCsp(parts.controller.sha256)}">`,
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escapeHtml(title)}</title>`,
    '<style>',
    parts.highlightCss,
    parts.pageCss,
    parts.handoutCss,
    '</style>',
    '</head>',
    `<body class="${HANDOUT_DOM.bodyClass}">`,
    `<main id="${HANDOUT_DOM.pagesId}">`,
    ...articles,
    '</main>',
    `<script type="application/json" id="${HANDOUT_DOM.tocDataId}">${tocJson}</script>`,
    `<script>${parts.controller.source}</script>`,
    '</body>',
    '</html>',
    '',
  ].join('\n')
}
