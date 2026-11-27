/**
 * The Handout's controller: the script inside the Handout that turns its pages into the Explainer's
 * paged panel. It is the only script the Handout's CSP lets run (by its hash).
 *
 * Why it exists: a colleague who did not watch the walkthrough reads it the way the walkthrough
 * showed it, one page at a time, with the header, the table of contents and the pager they would
 * have seen; a link to `#5` opens page 5. Without it (a mail preview) every page still reads top to
 * bottom. Listeners only, never inline handlers: the CSP's hash does not cover those.
 */
import {
  COPY_FEEDBACK_MS,
  DIAGRAM_NATURAL_SCALE,
  PANEL_MIN_WIDTH_PX,
  PANEL_VIEWPORT_MARGIN_PX,
  ZOOM_MAX,
  ZOOM_MIN,
  ZOOM_STEP,
} from '../constants'
import type { TocEntry } from '../dom'
import { HANDOUT_DOM } from '../dom'

/** Where the dragged panel width is remembered; null where the browser refuses storage. */
export type WidthStore = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

/** What a copy button says while it idles, after a copy, and when a copy failed. */
const COPY_LABELS = { idle: 'コピー', done: 'コピーしました', failed: 'コピーできませんでした' } as const

/** The header line of a page: `【section】title`, or the title alone for a page without a section. */
function headingOf(entry: TocEntry): string {
  return entry.section ? `【${entry.section}】${entry.title}` : entry.title
}

/** Where arrow keys keep their own meaning: fields, editable text, and a page's code, tables and diagrams. */
const ARROW_KEY_OWNERS = 'input, textarea, select, [contenteditable], pre, .table-wrap, .diagram'

/** The blocks of a page that can be wider than their box and scroll sideways. */
const SIDEWAYS_SCROLLERS = 'pre, .table-wrap, .diagram'

/**
 * Whether arrow keys typed at a target belong to it rather than to paging.
 *
 * @param target - The keydown event's target.
 * @param view - The Handout's window, whose Element class the target belongs to.
 * @returns true inside a field, editable text, a code block, a table or a diagram.
 *
 * @example
 * keepsArrowKeys(document.querySelector('input'), window) // true
 * keepsArrowKeys(document.body, window)                    // false
 */
function keepsArrowKeys(target: EventTarget | null, view: Window & typeof globalThis): boolean {
  return target instanceof view.Element && target.closest(ARROW_KEY_OWNERS) !== null
}

/**
 * Whether the reader pressed into a block that scrolls sideways (wider than its box): arrow keys
 * scroll it there, as the browser does, instead of turning the page.
 *
 * @param pressed - Where the reader last pressed the pointer, or null.
 * @returns true when that point lies in a code block, table or diagram wider than its box.
 *
 * @example
 * scrollsSideways(document.querySelector('pre code')) // true for a code line longer than the panel
 */
function scrollsSideways(pressed: Element | null): boolean {
  const block = pressed?.closest<HTMLElement>(SIDEWAYS_SCROLLERS)
  return Boolean(block && block.scrollWidth > block.clientWidth)
}

/**
 * Create an element with a class, attributes and text.
 *
 * @example
 * create(document, 'button', { className: 'btn', text: '‹', attributes: { 'aria-label': '前のページ' } })
 */
function create<Tag extends keyof HTMLElementTagNameMap>(
  doc: Document,
  tag: Tag,
  options: { className?: string; id?: string; text?: string; attributes?: Record<string, string> } = {},
): HTMLElementTagNameMap[Tag] {
  const element = doc.createElement(tag)
  if (options.className) element.className = options.className
  if (options.id) element.id = options.id
  if (options.text !== undefined) element.textContent = options.text
  for (const [name, value] of Object.entries(options.attributes ?? {})) element.setAttribute(name, value)
  return element
}

/**
 * Put a code block's text on the clipboard: the Clipboard API first, the selection and
 * `execCommand('copy')` where that API is missing or refuses (a file opened from disk in some browsers).
 *
 * @param doc - The Handout's document.
 * @param text - The code.
 * @returns Whether the text reached the clipboard; known only once the write settled.
 *
 * @example
 * await copyText(document, 'pnpm install') // true
 */
export async function copyText(doc: Document, text: string): Promise<boolean> {
  const clipboard = doc.defaultView?.navigator.clipboard
  try {
    if (clipboard) {
      await clipboard.writeText(text)
      return true
    }
  } catch {
    // Refused: try the selection below
  }
  const area = create(doc, 'textarea', { attributes: { readonly: '' } })
  area.value = text
  area.style.position = 'fixed'
  area.style.opacity = '0'
  doc.body.append(area)
  area.select()
  let copied = false
  try {
    copied = doc.execCommand('copy')
  } catch {
    copied = false
  }
  area.remove()
  return copied
}

/**
 * Take over the Handout: build the panel around its pages and wire every control.
 *
 * Called once by the controller's entry when the Handout loads; by specs with a document of their own.
 *
 * @param doc - The Handout's document, as the builder assembled it.
 * @param store - Where the dragged width is remembered (`localStorage`), or null.
 *
 * @example
 * startHandout(document, localStorage) // the panel shows page 1 (or #N), `data-handout-ready` is set
 */
export function startHandout(doc: Document, store: WidthStore | null): void {
  const view = doc.defaultView
  const pagesHolder = doc.getElementById(HANDOUT_DOM.pagesId)
  // The pages are the articles right under their holder: an element of a page's content sharing
  // their class is never a page of its own
  const pages = pagesHolder
    ? Array.from(pagesHolder.querySelectorAll<HTMLElement>(`:scope > article.${HANDOUT_DOM.pageClass}`))
    : []
  // Not a Handout this controller knows: leave the document as it is
  if (!view || !pagesHolder || pages.length === 0) return
  const toc: TocEntry[] = JSON.parse(doc.getElementById(HANDOUT_DOM.tocDataId)?.textContent ?? '[]')
  const total = pages.length
  const entryAt = (index: number): TocEntry => toc[index] ?? { n: index + 1, title: '', section: '' }

  // ---- the panel ----
  const panel = create(doc, 'div', { className: 'panel' })
  const leftEdge = create(doc, 'div', { className: 'edge left', attributes: { 'aria-hidden': 'true' } })
  const rightEdge = create(doc, 'div', { className: 'edge right', attributes: { 'aria-hidden': 'true' } })
  const header = create(doc, 'div', { className: 'header' })
  const pageNumber = create(doc, 'span', { id: HANDOUT_DOM.pageNumberId })
  const title = create(doc, 'span', { className: 'title' })
  const previousButton = create(doc, 'button', {
    className: 'btn',
    text: '‹',
    attributes: { 'aria-label': '前のページ', type: 'button' },
  })
  const nextButton = create(doc, 'button', {
    className: 'btn',
    text: '›',
    attributes: { 'aria-label': '次のページ', type: 'button' },
  })
  // The zoom controls share a class: a narrow window hides them (handout.css), the title keeps the room
  const zoomOutButton = create(doc, 'button', {
    className: 'btn zoom-control',
    text: '−',
    attributes: { 'aria-label': '縮小', type: 'button' },
  })
  const zoomLabel = create(doc, 'span', { className: 'zoom zoom-control' })
  const zoomInButton = create(doc, 'button', {
    className: 'btn zoom-control',
    text: '+',
    attributes: { 'aria-label': '拡大', type: 'button' },
  })
  const tocButton = create(doc, 'button', {
    className: 'btn',
    text: '☰',
    attributes: { 'aria-label': '目次', 'aria-expanded': 'false', type: 'button' },
  })
  header.append(
    create(doc, 'span', { className: 'heading', text: '解説' }),
    pageNumber,
    title,
    previousButton,
    nextButton,
    create(doc, 'span', { className: 'gap' }),
    zoomOutButton,
    zoomLabel,
    zoomInButton,
    tocButton,
  )
  const progress = create(doc, 'div', { className: 'progress' })
  const progressBar = create(doc, 'i')
  progress.append(progressBar)
  const tocPanel = create(doc, 'nav', { className: 'toc', attributes: { 'aria-label': '目次' } })
  tocPanel.hidden = true
  // Focusable by script: a page opened from a control that it hides takes the keyboard focus here
  const scroller = create(doc, 'div', { className: 'scroller', attributes: { tabindex: '-1' } })
  // What a screen reader says when the page changes: its number and title
  const announcer = create(doc, 'div', {
    className: 'announcer',
    attributes: { role: 'status', 'aria-live': 'polite' },
  })
  pagesHolder.replaceWith(panel)
  scroller.append(pagesHolder)
  panel.append(leftEdge, rightEdge, header, progress, tocPanel, scroller, announcer)

  // ---- pages ----
  let current = 1
  let zoom = 1

  /** Show page n (1..M): the others hidden, header, TOC and `#n` in step. */
  function show(requested: number): void {
    const n = Math.min(total, Math.max(1, Math.round(requested) || 1))
    current = n
    pages.forEach((page, index) => {
      page.hidden = index + 1 !== n
    })
    const entry = entryAt(n - 1)
    pageNumber.textContent = `${n}/${total}`
    title.textContent = headingOf(entry)
    announcer.textContent = `${n}/${total} ${headingOf(entry)}`
    previousButton.disabled = n === 1
    nextButton.disabled = n === total
    // Scaled, not resized: the bar's width never changes, so nothing is laid out again
    progressBar.style.transform = `scaleX(${n / total})`
    scroller.scrollTop = 0
    for (const item of tocPanel.querySelectorAll('button')) {
      if (Number(item.dataset.page) === n) item.setAttribute('aria-current', 'page')
      else item.removeAttribute('aria-current')
    }
    // A shared link opens the same page: the address follows the page shown
    if (view && view.location.hash !== `#${n}`) view.history.replaceState(null, '', `#${n}`)
  }

  /** The page an address names (`#5`), or null for any other address. */
  const pageFromHash = (): number | null => {
    const match = /^#(\d+)$/.exec(view.location.hash)
    return match ? Number(match[1]) : null
  }

  // The pager under each page: where the previous and next buttons lead, by title
  pages.forEach((page, index) => {
    const n = index + 1
    const pager = create(doc, 'nav', { className: 'pager', attributes: { 'aria-label': 'ページ送り' } })
    const link = (to: number, className: string, label: string) => {
      const button = create(doc, 'button', { className, attributes: { type: 'button' } })
      button.append(
        create(doc, 'small', { text: label }),
        create(doc, 'span', { text: entryAt(to - 1).title }),
      )
      // The button goes with the page it sits under: the keyboard focus moves to the page it opens
      button.addEventListener('click', () => {
        show(to)
        scroller.focus({ preventScroll: true })
      })
      return button
    }
    if (n > 1) pager.append(link(n - 1, 'prev', `‹ 前のページ（${n - 1}/${total}）`))
    if (n < total) pager.append(link(n + 1, 'next', `次のページ（${n + 1}/${total}）›`))
    page.append(pager)
  })

  // ---- table of contents ----
  toc.forEach((entry, index) => {
    const item = create(doc, 'button', { attributes: { type: 'button' } })
    item.dataset.page = String(index + 1)
    const label = create(doc, 'span')
    if (entry.section) label.append(create(doc, 'small', { text: entry.section }))
    label.append(doc.createTextNode(entry.title))
    item.append(create(doc, 'b', { text: String(index + 1) }), label)
    // The contents close with the choice: the keyboard focus moves to the page chosen
    item.addEventListener('click', () => {
      show(index + 1)
      setTocOpen(false)
      scroller.focus({ preventScroll: true })
    })
    tocPanel.append(item)
  })
  function setTocOpen(open: boolean): void {
    tocPanel.hidden = !open
    tocButton.setAttribute('aria-expanded', String(open))
  }
  tocButton.addEventListener('click', () => setTocOpen(tocPanel.hidden !== false))

  // ---- zoom ----
  function setZoom(requested: number): void {
    zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, Math.round(requested * 10) / 10))
    for (const page of pages) page.style.setProperty('zoom', String(zoom))
    zoomLabel.textContent = `${Math.round(zoom * 100)}%`
    zoomOutButton.disabled = zoom <= ZOOM_MIN
    zoomInButton.disabled = zoom >= ZOOM_MAX
  }
  zoomOutButton.addEventListener('click', () => setZoom(zoom - ZOOM_STEP))
  zoomInButton.addEventListener('click', () => setZoom(zoom + ZOOM_STEP))

  previousButton.addEventListener('click', () => show(current - 1))
  nextButton.addEventListener('click', () => show(current + 1))
  // The element the reader last pressed the pointer in: arrow keys scroll it when it scrolls sideways
  let pressedIn: Element | null = null
  doc.addEventListener('pointerdown', (event) => {
    pressedIn = event.target instanceof view.Element ? event.target : null
  })
  doc.addEventListener('keydown', (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey) return
    if (event.key === 'Escape') {
      // Closing the contents from inside them gives the focus back to the button that opened them
      const focusInside = tocPanel.contains(doc.activeElement)
      setTocOpen(false)
      if (focusInside) tocButton.focus()
      return
    }
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return
    // Arrow keys belong to a field, to a code block, table or diagram they were typed in, and to one the
    // reader pressed into that scrolls sideways; anywhere else they turn the page
    if (event.defaultPrevented || keepsArrowKeys(event.target, view) || scrollsSideways(pressedIn)) return
    show(event.key === 'ArrowRight' ? current + 1 : current - 1)
  })
  view.addEventListener('hashchange', () => {
    const requested = pageFromHash()
    if (requested !== null && requested !== current) show(requested)
  })

  // ---- code copy ----
  for (const code of pages.flatMap((page) => Array.from(page.querySelectorAll<HTMLElement>('pre > code')))) {
    const button = create(doc, 'button', {
      className: 'copy',
      text: COPY_LABELS.idle,
      attributes: { type: 'button' },
    })
    button.addEventListener('click', async () => {
      // Say it is done only once the clipboard took the text
      const copied = await copyText(doc, code.textContent ?? '')
      button.textContent = copied ? COPY_LABELS.done : COPY_LABELS.failed
      view.setTimeout(() => {
        button.textContent = COPY_LABELS.idle
      }, COPY_FEEDBACK_MS)
    })
    code.parentElement?.append(button)
  }

  // ---- diagrams: a click toggles between fitting the width and natural size ----
  for (const holder of doc.querySelectorAll<HTMLElement>('.diagram')) {
    holder.addEventListener('click', () => {
      const graphic = holder.querySelector<SVGSVGElement>('svg')
      if (!graphic) return
      const wide = holder.classList.toggle('wide')
      const natural = graphic.viewBox?.baseVal?.width ?? 0
      if (!graphic.dataset.fitted) graphic.dataset.fitted = graphic.style.maxWidth || '100%'
      graphic.style.maxWidth = wide ? 'none' : graphic.dataset.fitted
      graphic.style.width = wide && natural ? `${Math.round(natural * DIAGRAM_NATURAL_SCALE)}px` : ''
    })
  }

  // ---- width: dragged from either edge, symmetric, remembered for this file ----
  const widthKey = `dw-handout-width:${view.location.pathname}`
  const minWidth = () => Math.min(PANEL_MIN_WIDTH_PX, view.innerWidth - PANEL_VIEWPORT_MARGIN_PX)
  const maxWidth = () => view.innerWidth - PANEL_VIEWPORT_MARGIN_PX
  const clampWidth = (width: number) => Math.max(minWidth(), Math.min(maxWidth(), width))
  const stored = Number(store?.getItem(widthKey))
  /** The width the reader dragged to; null keeps the default, min(900px, window − 32px). */
  let draggedWidth: number | null = Number.isFinite(stored) && stored > 0 ? stored : null
  const applyWidth = () => {
    panel.style.width = draggedWidth === null ? '' : `${clampWidth(draggedWidth)}px`
  }
  // A drag ends however the pointer leaves it: released, cancelled by the system (a gesture, a
  // window switch) or its capture lost; otherwise the edge would go on following a pointer no one holds
  const dragEndEvents = ['pointerup', 'pointercancel', 'lostpointercapture'] as const
  for (const edge of [leftEdge, rightEdge]) {
    edge.addEventListener('pointerdown', (event) => {
      event.preventDefault()
      edge.setPointerCapture?.(event.pointerId)
      const box = panel.getBoundingClientRect()
      const center = box.left + box.width / 2
      const move = (dragEvent: PointerEvent) => {
        draggedWidth = clampWidth(2 * Math.abs(dragEvent.clientX - center))
        applyWidth()
      }
      const end = () => {
        edge.removeEventListener('pointermove', move)
        for (const type of dragEndEvents) edge.removeEventListener(type, end)
        if (draggedWidth !== null) store?.setItem(widthKey, String(Math.round(draggedWidth)))
      }
      edge.addEventListener('pointermove', move)
      for (const type of dragEndEvents) edge.addEventListener(type, end)
    })
    edge.addEventListener('dblclick', () => {
      draggedWidth = null
      store?.removeItem(widthKey)
      applyWidth()
    })
  }
  view.addEventListener('resize', applyWidth)

  applyWidth()
  setZoom(1)
  show(pageFromHash() ?? 1)
  doc.documentElement.setAttribute(HANDOUT_DOM.readyAttribute, '')
}
