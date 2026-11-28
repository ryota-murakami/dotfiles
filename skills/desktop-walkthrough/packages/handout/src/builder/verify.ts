import { maskSecrets } from '../../../../hooks/secrets'
import type { Diagnostic } from '../contract'
import { excerpt } from '../utils/excerpt'
import type { HandoutCheck } from './probes'

/** The labels of one diagram, by the id page.html gave its SVG in Handout mode (`p2-d1`). */
export interface DiagramLabels {
  id: string
  labels: string[]
}

/** Page and diagram numbers from a Handout-mode SVG id (`p2-d1`); nothing for another id. */
function locate(id: string): { page?: number; diagram?: number } {
  const match = /^p(\d+)-d(\d+)$/.exec(id)
  return match ? { page: Number(match[1]), diagram: Number(match[2]) } : {}
}

/**
 * Judge the finished Handout as the colleague will open it (eng D10): under its own CSP, did the
 * controller take over and page by `#N`, and does every diagram still carry the labels it had
 * before sanitizing?
 *
 * Why it exists: the checks on each page run before sanitizing and before the CSP; a sanitizer
 * setting that drops labels, or a CSP that blocks the controller, would pass all of them and ship a
 * broken file as verified. Called by {@link buildHandout} last, before the host publishes.
 *
 * @param expected - Each diagram's labels as measured in the rendered page, before sanitizing.
 * @param check - What {@link checkHandout} saw in the reopened file.
 * @param pageCount - Pages in the Handout.
 * @returns HANDOUT_VERIFY diagnostics, and HANDOUT_IMAGE for a picture that does not decode; empty
 * when the file works as checked.
 *
 * @example
 * judgeVerification([{ id: 'p2-d1', labels: ['書き出す'] }], { ready: true, pages: 3, pageNumber: '1/3', secondShown: true, diagrams: [{ id: 'p2-d1', labels: [] }] }, 3)
 * // [{ code: 'HANDOUT_VERIFY', page: 2, diagram: 1, message: 'the finished Handout lost labels of diagram 1 on page 2: 「書き出す」' }]
 */
export function judgeVerification(
  expected: readonly DiagramLabels[],
  check: HandoutCheck,
  pageCount: number,
): Diagnostic[] {
  const diagnostics: Diagnostic[] = []
  // Without its controller the file still reads, but it is not the Handout that was checked
  if (!check.ready) {
    diagnostics.push({
      code: 'HANDOUT_VERIFY',
      message: "the finished Handout's controller did not run when it was opened (its CSP may block it)",
    })
  } else {
    if (check.pageNumber !== `1/${pageCount}`) {
      diagnostics.push({
        code: 'HANDOUT_VERIFY',
        message: `the finished Handout shows "${excerpt(check.pageNumber)}" in its header instead of 1/${pageCount}`,
      })
    }
    if (pageCount >= 2 && check.secondShown !== true) {
      diagnostics.push({ code: 'HANDOUT_VERIFY', message: 'the finished Handout did not open page 2 for #2' })
    }
  }
  // A picture whose bytes passed every check before can still be cut off: it shows as a broken image
  for (const broken of check.brokenImages) {
    diagnostics.push({
      code: 'HANDOUT_IMAGE',
      message: `page ${broken.page}: picture ${broken.image} does not show in the finished Handout: its bytes are a broken or cut-off picture; save it again, then export again`,
      page: broken.page,
    })
  }
  for (const diagram of expected) {
    const location = locate(diagram.id)
    const where =
      location.page === undefined
        ? `diagram ${diagram.id}`
        : `diagram ${location.diagram} on page ${location.page}`
    const found = check.diagrams.find((candidate) => candidate.id === diagram.id)
    if (!found) {
      diagnostics.push({ code: 'HANDOUT_VERIFY', message: `the finished Handout lost ${where}`, ...location })
      continue
    }
    const lost = diagram.labels.filter((label, index) => found.labels[index] !== label)
    if (lost.length === 0 && found.labels.length === diagram.labels.length) continue
    const quoted = lost.length > 0 ? `: 「${excerpt(maskSecrets(lost.join('」「')))}」` : ''
    diagnostics.push({
      code: 'HANDOUT_VERIFY',
      message: `the finished Handout lost labels of ${where}${quoted}`,
      ...location,
    })
  }
  return diagnostics
}
