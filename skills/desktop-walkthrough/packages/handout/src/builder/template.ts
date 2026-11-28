/** Comment in page.html's `<style>` where the reading-marks CSS begins; the Handout leaves that CSS out. */
export const READING_MARKS_BEGIN = '/* handout: reading marks begin */'

/** Comment in page.html's `<style>` where the reading-marks CSS ends. */
export const READING_MARKS_END = '/* handout: reading marks end */'

/** The CSS the Handout takes from page.html, or why it could not be taken. */
export type TemplateCss = { ok: true; css: string } | { ok: false; reason: string }

/**
 * Take the Explainer's look from page.html at every export: its `<style>` without the reading marks.
 *
 * Why it exists: the Handout must look like the HUD's Explainer without copying its CSS by hand,
 * and reading marks have no place in a file nobody reports reading to. The markers make the cut
 * explicit; a page.html without them stops the export (HANDOUT_TEMPLATE) instead of shipping marks.
 * Called by {@link buildHandout} before any page is rendered.
 *
 * @param template - The text of explainer/page.html.
 * @returns
 * - `{ ok: true, css }`: the first `<style>` block's CSS, the marked section cut out
 * - `{ ok: false, reason }`: no `<style>` block, or a marker missing or out of order
 *
 * @example
 * handoutCss(`<style>a{} ${READING_MARKS_BEGIN} .rd-mark{} ${READING_MARKS_END} b{}</style>`)
 * // { ok: true, css: 'a{}  b{}' }
 * handoutCss('<style>a{}</style>') // { ok: false, reason: 'the reading-marks markers are missing from its <style>' }
 */
export function handoutCss(template: string): TemplateCss {
  const style = /<style>([\s\S]*?)<\/style>/.exec(template)?.[1]
  if (style === undefined) return { ok: false, reason: 'it has no <style> block' }
  const begin = style.indexOf(READING_MARKS_BEGIN)
  const end = style.indexOf(READING_MARKS_END)
  if (begin < 0 || end < 0)
    return { ok: false, reason: 'the reading-marks markers are missing from its <style>' }
  if (end < begin) return { ok: false, reason: 'the reading-marks end marker comes before its begin marker' }
  return { ok: true, css: style.slice(0, begin) + style.slice(end + READING_MARKS_END.length) }
}
