import { maskSecrets } from '../../../../hooks/secrets'
import { OVERFLOW_TOLERANCE_PX } from '../constants'
import type { Diagnostic, HandoutPage, PageLibrary, RenderReport } from '../contract'
import { pageLibrarySchema } from '../contract'
import { excerpt } from '../utils/excerpt'
import { mermaidFenceLines } from '../utils/mermaidFenceLines'
import type { PageMeasurement } from './probes'

/** A render-report error that names a diagram: `diagram 2: Parse error on line 3 …`. */
const DIAGRAM_ERROR = /^diagram (\d+): ([\s\S]*)$/

/** A render-report error of an audience marker the page met as HTML: `marker: …` (page.html, Handout mode). */
const MARKER_ERROR = /^marker: /

/**
 * The libraries a Handout-mode page did not report as loaded (eng C9).
 *
 * @param report - The page's render report.
 * @returns Every library of {@link pageLibrarySchema} missing from `libs`; all of them when `libs` is absent.
 *
 * @example
 * missingLibraries({ type: 'rendered', page: 1, diagrams: 0, errors: [], libs: ['marked', 'highlight'] })
 * // ['highlight-http', 'mermaid', 'purify']
 */
export function missingLibraries(report: RenderReport): PageLibrary[] {
  const loaded = new Set(report.libs ?? [])
  return pageLibrarySchema.options.filter((library) => !loaded.has(library))
}

/**
 * Judge one rendered page: diagrams that failed, diagrams nothing was laid out for, labels that do
 * not fit their box (DX D9, eng C6a), and audience markers the page met as HTML, which dw's filter
 * never read (HANDOUT_MARKER). Library problems are judged once per run by the caller.
 *
 * Why it exists: an agent fixes what the export names, so every problem carries the page, the
 * diagram and the line of its fence in the original source. Error texts and labels pass
 * {@link maskSecrets} and are cut short. Called by {@link buildHandout} for every page.
 *
 * @param page - The page as dw listed it.
 * @param report - What page.html reported once it rendered.
 * @param measurement - What {@link measurePage} measured.
 * @returns HANDOUT_DIAGRAM and HANDOUT_OVERFLOW diagnostics; empty for a page that rendered well.
 *
 * @example
 * judgeRenderedPage(page, { …, errors: ['diagram 1: Parse error on line 2'] }, measurement)
 * // [{ code: 'HANDOUT_DIAGRAM', page: 2, diagram: 1, line: 5, message: 'page 2:5: diagram 1 did not render: Parse error on line 2' }]
 */
export function judgeRenderedPage(
  page: HandoutPage,
  report: RenderReport,
  measurement: PageMeasurement,
): Diagnostic[] {
  const fenceLines = mermaidFenceLines(page.markdown)
  /** `page 2:5` for diagram K when its fence was found, else the page alone. */
  const at = (diagram: number) => {
    const line = fenceLines[diagram - 1]
    return line === undefined ? { where: `page ${page.n}` } : { where: `page ${page.n}:${line}`, line }
  }
  const diagnostics: Diagnostic[] = []
  const failed = new Set<number>()
  for (const error of report.errors) {
    // A marker the page met as HTML: its block would reach the wrong audience (page.html, Handout mode)
    if (MARKER_ERROR.test(error)) {
      diagnostics.push({
        code: 'HANDOUT_MARKER',
        message: `page ${page.n}: an audience marker reached the page as HTML: dw did not read it (a code fence that opens inside a list item or a quote, or a list that ends inside one, hides the markers after it); put each fence and marker at the left edge, then export again`,
        page: page.n,
      })
      continue
    }
    const match = DIAGRAM_ERROR.exec(error)
    // Errors that name no diagram are a missing library: the caller reports those once
    if (!match?.[1]) continue
    const diagram = Number(match[1])
    const { where, line } = at(diagram)
    failed.add(diagram)
    diagnostics.push({
      code: 'HANDOUT_DIAGRAM',
      message: `${where}: diagram ${diagram} did not render: ${excerpt(maskSecrets(match[2] ?? ''))}`,
      page: page.n,
      diagram,
      ...(line === undefined ? {} : { line }),
    })
  }
  measurement.diagrams.forEach((measured, index) => {
    const diagram = index + 1
    if (failed.has(diagram)) return
    const { where, line } = at(diagram)
    const location = { page: page.n, diagram, ...(line === undefined ? {} : { line }) }
    const labels = measured.labels.filter((label) => label.text !== '')
    // Fail closed: without a laid-out label the overflow check would pass on nothing (eng C6a)
    if (!labels.some((label) => label.width > 0 && label.height > 0)) {
      diagnostics.push({
        code: 'HANDOUT_DIAGRAM',
        message: `${where}: diagram ${diagram} has no label with a size: nothing was laid out to check`,
        ...location,
      })
      return
    }
    for (const label of labels) {
      // A label with text but neither a box nor content was not laid out: what it says is not shown
      if (label.width <= 0 && label.height <= 0 && label.contentWidth <= 0 && label.contentHeight <= 0) {
        diagnostics.push({
          code: 'HANDOUT_DIAGRAM',
          message: `${where}: diagram ${diagram}: the label 「${excerpt(maskSecrets(label.text))}」 was not laid out (it has no size): a style on the page hides diagram text, or the diagram did not finish drawing; remove the style and export again`,
          ...location,
        })
        continue
      }
      const tooWide = label.contentWidth > label.width + OVERFLOW_TOLERANCE_PX
      const tooTall = label.contentHeight > label.height + OVERFLOW_TOLERANCE_PX
      if (!tooWide && !tooTall) continue
      const needs = `${Math.round(label.contentWidth)}×${Math.round(label.contentHeight)}`
      const has = `${Math.round(label.width)}×${Math.round(label.height)}`
      diagnostics.push({
        code: 'HANDOUT_OVERFLOW',
        message: `${where}: diagram ${diagram}: the label 「${excerpt(maskSecrets(label.text))}」 needs ${needs} px in a ${has} px box: a style on the page changes diagram text, or a font loaded late; remove the style or shorten the label`,
        ...location,
      })
    }
  })
  return diagnostics
}
