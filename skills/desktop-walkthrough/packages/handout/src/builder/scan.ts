import { findSecrets, maskSecrets } from '../../../../hooks/secrets'
import type { Diagnostic, HandoutPage } from '../contract'

/**
 * Find every secret shape in what the Handout would carry, before anything is rendered (DX D8).
 *
 * Why it exists: a Handout leaves the machine. A signed link behind harmless link text or a key in
 * a diagram source would reach a colleague's inbox, so the export stops and names where each one is.
 * Reads the page sources (link targets and diagram sources included), titles and section names.
 * Called first by {@link buildHandout}.
 *
 * @param pages - The Record's pages as dw listed them.
 * @returns One HANDOUT_SECRET per finding, with page, line and shape name; empty when nothing was found.
 *
 * @example
 * scanForSecrets([{ n: 2, source: 'pages/02-設定.md', markdown: '…?signature=0f3a…\n', title: '設定', section: '', built: 'pages/002.html' }])
 * // [{ code: 'HANDOUT_SECRET', page: 2, line: 1, pattern: 'signed-url-parameter',
 * //    message: 'pages/02-設定.md:1: a secret shape (signed-url-parameter); remove the value from the page' }]
 */
export function scanForSecrets(pages: readonly HandoutPage[]): Diagnostic[] {
  const diagnostics: Diagnostic[] = []
  for (const page of pages) {
    const source = maskSecrets(page.source)
    for (const finding of findSecrets(page.markdown)) {
      diagnostics.push({
        code: 'HANDOUT_SECRET',
        message: `${source}:${finding.line}: a secret shape (${finding.pattern}); remove the value from the page`,
        page: page.n,
        line: finding.line,
        pattern: finding.pattern,
      })
    }
    // A title that is the page's H1 was found in the source above; one given with --title was not
    if (!page.markdown.includes(page.title)) {
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
