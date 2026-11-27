import createDOMPurify from 'dompurify'
import type { Config } from 'dompurify'

/**
 * The allowlist of the assembled Handout (DX D14, eng A1). HTML and SVG as DOMPurify allows them by
 * default, plus what mermaid draws with: its flowchart labels are HTML inside `<foreignObject>`,
 * which DOMPurify drops by default (34 labels in the 12-page prototype), and its SVG carries a
 * `<style>`. Scripts, event handlers, `javascript:` links and frames stay out.
 */
const SANITIZE_CONFIG: Config = {
  USE_PROFILES: { html: true, svg: true, svgFilters: true },
  ADD_TAGS: ['foreignobject'],
  HTML_INTEGRATION_POINTS: { foreignobject: true },
  ADD_ATTR: ['target'],
}

/** An instance of its own, so the link hook below never touches another user of DOMPurify. */
let purifier: ReturnType<typeof createDOMPurify> | null = null

/** The Handout's DOMPurify, created on first use against the page's own window. */
function handoutPurifier(): ReturnType<typeof createDOMPurify> {
  if (purifier) return purifier
  const created = createDOMPurify(window)
  // A link opens in a new tab: following it must not lose the reader's place in the Handout
  created.addHook('afterSanitizeAttributes', (node) => {
    if (node.nodeName !== 'A' || !/^https?:/i.test(node.getAttribute('href') ?? '')) return
    node.setAttribute('target', '_blank')
    node.setAttribute('rel', 'noopener noreferrer')
  })
  purifier = created
  return created
}

/**
 * Sanitize one page's rendered content for the Handout.
 *
 * Why it exists: a page is Markdown, and Markdown passes HTML through: an `<img onerror>` the agent
 * wrote (or pasted) would run in the colleague's browser. Called by {@link buildHandout} for every
 * page after images are embedded; the CSP of the Handout is the second line.
 *
 * @param html - A page's content, images embedded.
 * @returns The same content without anything that runs.
 *
 * @example
 * sanitizePage('<p onclick="x()">本文</p><script>x()</script>') // '<p>本文</p>'
 * sanitizePage('<svg><foreignObject><div><span>書き出す</span></div></foreignObject></svg>') // unchanged
 */
export function sanitizePage(html: string): string {
  return handoutPurifier().sanitize(html, SANITIZE_CONFIG)
}

/**
 * The label texts of every diagram in some content, by the diagram's SVG id, as the verify probe
 * reads them (foreignObject and SVG text, empty ones left out).
 *
 * @param html - A page's content.
 * @returns The labels of each diagram in reading order.
 *
 * @example
 * diagramLabels('<div class="diagram"><svg id="p2-d1">…<foreignObject><div>書き出す</div></foreignObject>…</svg></div>')
 * // [{ id: 'p2-d1', labels: ['書き出す'] }]
 */
export function diagramLabels(html: string): Array<{ id: string; labels: string[] }> {
  const holder = document.createElement('template')
  holder.innerHTML = html
  return Array.from(holder.content.querySelectorAll('.diagram svg')).map((svg) => ({
    id: svg.id,
    labels: Array.from(svg.querySelectorAll('foreignObject, text'))
      .map((label) => (label.textContent ?? '').trim())
      .filter((text) => text !== ''),
  }))
}
