import createDOMPurify from 'dompurify'
import type { Config } from 'dompurify'

import { HANDOUT_DOM } from '../dom'

/**
 * The allowlist of the assembled Handout (DX D14, eng A1). HTML and SVG as DOMPurify allows them by
 * default, plus what mermaid draws with: its flowchart labels are HTML inside `<foreignObject>`,
 * which DOMPurify drops by default (34 labels in the 12-page prototype), and its SVG carries a
 * `<style>`. Scripts, event handlers, `javascript:` links and frames stay out, and so do responsive
 * image alternatives (`srcset`, `<source>`): only the embedded `src` exists in the finished file.
 */
const SANITIZE_CONFIG: Config = {
  USE_PROFILES: { html: true, svg: true, svgFilters: true },
  ADD_TAGS: ['foreignobject'],
  HTML_INTEGRATION_POINTS: { foreignobject: true },
  ADD_ATTR: ['target'],
  // A template's contents ship in the file though no reader sees them
  FORBID_TAGS: ['source', 'template'],
  FORBID_ATTR: ['srcset'],
}

/** Ids the Handout's own page uses (its pages' holder, its table of contents, its page number). */
const RESERVED_IDS: ReadonlySet<string> = new Set([
  HANDOUT_DOM.pagesId,
  HANDOUT_DOM.tocDataId,
  HANDOUT_DOM.pageNumberId,
])

/** A page's position id (`page-3`), which `#3` and the verify probe look up. */
const PAGE_POSITION_ID = new RegExp(`^${HANDOUT_DOM.pageIdPrefix}\\d+$`)

/** An instance of its own, so the link hook below never touches another user of DOMPurify. */
let purifier: ReturnType<typeof createDOMPurify> | null = null

/** The Handout's DOMPurify, created on first use against the page's own window. */
function handoutPurifier(): ReturnType<typeof createDOMPurify> {
  if (purifier) return purifier
  const created = createDOMPurify(window)
  // A link opens in a new tab: following it must not lose the reader's place in the Handout. An SVG
  // link (a diagram's) is an `a` in lower case, its address in href or xlink:href
  created.addHook('afterSanitizeAttributes', (node) => {
    if (node.localName !== 'a') return
    const address = node.getAttribute('href') ?? node.getAttribute('xlink:href') ?? ''
    if (!/^https?:/i.test(address)) return
    node.setAttribute('target', '_blank')
    node.setAttribute('rel', 'noopener noreferrer')
  })
  // A page's element with an id the Handout's own page uses would take over the controller's lookups
  created.addHook('uponSanitizeAttribute', (_node, data) => {
    if (data.attrName === 'id' && (RESERVED_IDS.has(data.attrValue) || PAGE_POSITION_ID.test(data.attrValue)))
      data.keepAttr = false
  })
  purifier = created
  return created
}

/**
 * Sanitize one page's rendered content for the Handout.
 *
 * Why it exists: a page is Markdown, and Markdown passes HTML through: an `<img onerror>` the agent
 * wrote (or pasted) would run in the colleague's browser. Called by {@link buildHandout} for every
 * page after images are embedded; the CSP of the Handout is the second line. Pages share one file,
 * so what one page brings must not reach another: its own `<style>` (outside an SVG) and ids the
 * Handout's page uses (`handout-toc`, `page-2`, `pageno`) go too.
 *
 * @param html - A page's content, images embedded.
 * @returns The same content without anything that runs or reaches beyond the page.
 *
 * @example
 * sanitizePage('<p onclick="x()">本文</p><script>x()</script>') // '<p>本文</p>'
 * sanitizePage('<svg><foreignObject><div><span>書き出す</span></div></foreignObject></svg>') // unchanged
 * sanitizePage('<p>本文</p><style>h1 { color: red }</style>') // '<p>本文</p>'
 */
export function sanitizePage(html: string): string {
  const fragment = handoutPurifier().sanitize(html, { ...SANITIZE_CONFIG, RETURN_DOM_FRAGMENT: true })
  // A page's own <style> would apply to every page of the one file a Handout is, though each page
  // was measured alone; mermaid's styles sit inside its SVG, scoped by the diagram's id
  // A style inside a diagram's HTML label (foreignObject) is the page's HTML: it goes too
  for (const style of Array.from(fragment.querySelectorAll('style'))) {
    const ownedByDiagram = style.parentElement?.localName === 'svg' && style.closest('foreignObject') === null
    if (!ownedByDiagram) style.remove()
  }
  // Read back in a document without a window: nothing in it loads (an image of a page fetches nothing)
  const holder = document.implementation.createHTMLDocument('').createElement('div')
  holder.append(fragment)
  return holder.innerHTML
}
