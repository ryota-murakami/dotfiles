import { afterEach, beforeEach, expect, test, vi } from 'vitest'

import { assembleHandout } from '../builder/assemble'
import type { WidthStore } from './controller'
import { startHandout } from './controller'

const PAGES = [
  {
    n: 1,
    title: '書き出しの流れ',
    section: '準備',
    html: '<h1>書き出しの流れ</h1><pre><code>pnpm install</code></pre>',
  },
  {
    n: 2,
    title: '判定の仕組み',
    section: '仕組み',
    html: '<h1>判定の仕組み</h1><div class="diagram"><svg id="p2-d1" viewBox="0 0 400 100" style="max-width: 400px;"></svg></div>',
  },
  { n: 3, title: '<script>確認</script>', section: '', html: '<h1>確認</h1>' },
]

/** Put an assembled Handout's body into the test document, the way the browser would load it. */
function loadHandout(pages: typeof PAGES = PAGES): void {
  const html = assembleHandout({
    pages,
    pageCss: '',
    highlightCss: '',
    handoutCss: '',
    controller: { source: '', sha256: 'eA==' },
  })
  document.body.innerHTML = new DOMParser().parseFromString(html, 'text/html').body.innerHTML
}

/** A remembered-width store backed by a map, so a spec can read what the controller kept. */
function memoryStore(initial: Record<string, string> = {}): WidthStore & { values: Map<string, string> } {
  const values = new Map(Object.entries(initial))
  return {
    values,
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => void values.set(key, value),
    removeItem: (key) => void values.delete(key),
  }
}

const visiblePages = () =>
  Array.from(document.querySelectorAll<HTMLElement>('article.page'))
    .filter((page) => !page.hidden)
    .map((page) => page.id)

const headerText = () =>
  `${document.getElementById('pageno')?.textContent} ${document.querySelector('.header .title')?.textContent}`

/** Press a key the way a reader does, on the document. */
function press(key: string): void {
  document.dispatchEvent(new KeyboardEvent('keydown', { key }))
}

/** The zoom the header shows. */
const zoomLabel = () => document.querySelector('.zoom')?.textContent

beforeEach(() => {
  history.replaceState(null, '', '#')
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1200 })
})

afterEach(() => {
  vi.restoreAllMocks()
  document.body.innerHTML = ''
  document.documentElement.removeAttribute('data-handout-ready')
})

test('the Handout opens on page 1, counts its pages in the header and marks itself ready', () => {
  // Arrange
  loadHandout()

  // Act
  startHandout(document, memoryStore())

  // Assert
  expect(visiblePages()).toEqual(['page-1'])
  expect(headerText()).toBe('1/3 【準備】書き出しの流れ')
  expect(document.documentElement.hasAttribute('data-handout-ready')).toBe(true)
})

test('a shared link to #2 opens page 2', () => {
  // Arrange
  loadHandout()
  history.replaceState(null, '', '#2')

  // Act
  startHandout(document, memoryStore())

  // Assert
  expect(visiblePages()).toEqual(['page-2'])
  expect(headerText()).toBe('2/3 【仕組み】判定の仕組み')
})

test('changing the address to #3 while reading opens page 3', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())

  // Act
  location.hash = '#3'
  window.dispatchEvent(new HashChangeEvent('hashchange'))

  // Assert
  expect(visiblePages()).toEqual(['page-3'])
})

test('the button under a page leads to the next page and names it', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const next = document.querySelector<HTMLButtonElement>('#page-1 .pager .next')

  // Act
  next?.click()

  // Assert
  expect(next?.textContent).toBe('次のページ（2/3）›判定の仕組み')
  expect(visiblePages()).toEqual(['page-2'])
  expect(location.hash).toBe('#2')
})

test('arrow keys page through the Handout and stop at its ends', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())

  // Act
  press('ArrowLeft')
  const atStart = visiblePages()
  press('ArrowRight')
  press('ArrowRight')
  press('ArrowRight')
  const atEnd = visiblePages()

  // Assert
  expect(atStart).toEqual(['page-1'])
  expect(atEnd).toEqual(['page-3'])
})

test('an arrow key past the first or last page keeps the reader where they were on that page', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const scroller = document.querySelector<HTMLElement>('.scroller')
  if (!scroller) throw new Error('the Handout has no scroller')
  scroller.scrollTop = 120
  press('ArrowLeft')
  const onFirst = scroller.scrollTop
  press('ArrowRight')
  press('ArrowRight')
  scroller.scrollTop = 240

  // Act
  press('ArrowRight')

  // Assert
  expect(onFirst).toBe(120)
  expect(visiblePages()).toEqual(['page-3'])
  expect(scroller.scrollTop).toBe(240)
})

test('the table of contents jumps to a page and closes; Esc closes it too', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const tocButton = document.querySelector<HTMLButtonElement>('.btn[aria-label="目次"]')
  const toc = document.querySelector<HTMLElement>('nav.toc')

  // Act
  tocButton?.click()
  const openedWith = toc?.hidden
  document.querySelector<HTMLButtonElement>('nav.toc button[data-page="3"]')?.click()
  const afterJump = toc?.hidden
  tocButton?.click()
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))

  // Assert
  expect(openedWith).toBe(false)
  expect(afterJump).toBe(true)
  expect(visiblePages()).toEqual(['page-3'])
  expect(toc?.hidden).toBe(true)
})

test('opening the table of contents on a late page brings that page’s row into view', () => {
  // Arrange
  location.hash = '#3'
  loadHandout()
  startHandout(document, memoryStore())
  const scrolled: string[] = []
  const scrollIntoView = vi.fn(function (this: Element) {
    scrolled.push(this.getAttribute('data-page') ?? '')
  })
  Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', {
    configurable: true,
    value: scrollIntoView,
  })

  // Act
  document.querySelector<HTMLButtonElement>('.btn[aria-label="目次"]')?.click()

  // Assert
  expect(scrolled).toEqual(['3'])
  expect(scrollIntoView).toHaveBeenCalledWith({ block: 'nearest' })
})

test('Shift with an arrow key extends a selection and leaves the page where it is', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())

  // Act
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', shiftKey: true }))

  // Assert
  expect(visiblePages()).toEqual(['page-1'])
})

test('a page title that spells markup shows as text in the table of contents', () => {
  // Arrange
  loadHandout()

  // Act
  startHandout(document, memoryStore())

  // Assert
  const item = document.querySelector('nav.toc button[data-page="3"]')
  expect(item?.textContent).toBe('3<script>確認</script>')
  expect(item?.querySelector('script')).toBeNull()
})

test('zoom steps by 10% and stays between 80% and 160%', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const zoomIn = document.querySelector<HTMLButtonElement>('.btn[aria-label="拡大"]')
  const zoomOut = document.querySelector<HTMLButtonElement>('.btn[aria-label="縮小"]')

  // Act
  for (let clicks = 0; clicks < 10; clicks += 1) zoomIn?.click()
  const largest = zoomLabel()
  for (let clicks = 0; clicks < 10; clicks += 1) zoomOut?.click()
  const smallest = zoomLabel()

  // Assert
  expect(largest).toBe('160%')
  expect(smallest).toBe('80%')
  expect(document.querySelector<HTMLElement>('#page-1')?.style.getPropertyValue('zoom')).toBe('0.8')
})

test('copy says it is done only after the clipboard took the text', async () => {
  // Arrange
  loadHandout()
  let accept: (() => void) | undefined
  const writeText = vi.fn(() => new Promise<void>((resolve) => (accept = resolve)))
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } })
  startHandout(document, memoryStore())
  const button = document.querySelector<HTMLButtonElement>('#page-1 pre .copy')

  // Act
  button?.click()
  const whileWriting = button?.textContent
  accept?.()
  await vi.waitFor(() => expect(button?.textContent).toBe('コピーしました'))

  // Assert
  expect(whileWriting).toBe('コピー')
  expect(writeText).toHaveBeenCalledWith('pnpm install')
})

test('copy falls back to the selection when the clipboard refuses a file opened from disk', async () => {
  // Arrange
  loadHandout()
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText: () => Promise.reject(new Error('NotAllowedError')) },
  })
  const execCommand = vi.fn(() => true)
  Object.defineProperty(document, 'execCommand', { configurable: true, value: execCommand })
  startHandout(document, memoryStore())
  const button = document.querySelector<HTMLButtonElement>('#page-1 pre .copy')

  // Act
  button?.click()

  // Assert
  await vi.waitFor(() => expect(button?.textContent).toBe('コピーしました'))
  expect(execCommand).toHaveBeenCalledWith('copy')
})

test('copy says it failed when neither the clipboard nor the selection works', async () => {
  // Arrange
  loadHandout()
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText: () => Promise.reject(new Error('NotAllowedError')) },
  })
  Object.defineProperty(document, 'execCommand', { configurable: true, value: () => false })
  startHandout(document, memoryStore())
  const button = document.querySelector<HTMLButtonElement>('#page-1 pre .copy')

  // Act
  button?.click()

  // Assert
  await vi.waitFor(() => expect(button?.textContent).toBe('コピーできませんでした'))
})

test('a click on a diagram shows it at natural size, a second click fits it again', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const holder = document.querySelector<HTMLElement>('#page-2 .diagram')
  const graphic = holder?.querySelector('svg')

  // Act
  holder?.click()
  const wide = { maxWidth: graphic?.style.maxWidth, width: graphic?.style.width }
  holder?.click()

  // Assert
  expect(wide).toEqual({ maxWidth: 'none', width: '500px' })
  expect(graphic?.style.maxWidth).toBe('400px')
  expect(graphic?.style.width).toBe('')
})

test('dragging an edge widens the panel on both sides and remembers the width for this file', () => {
  // Arrange
  loadHandout()
  const store = memoryStore()
  startHandout(document, store)
  const edge = document.querySelector<HTMLElement>('.edge.right')
  const panel = document.querySelector<HTMLElement>('.panel')

  // Act
  edge?.dispatchEvent(new PointerEvent('pointerdown', { clientX: 450, pointerId: 1 }))
  edge?.dispatchEvent(new PointerEvent('pointermove', { clientX: 500, pointerId: 1 }))
  edge?.dispatchEvent(new PointerEvent('pointerup', { clientX: 500, pointerId: 1 }))

  // Assert
  expect(panel?.style.width).toBe('1000px')
  expect([...store.values]).toEqual([[`dw-handout-width:${location.pathname}`, '1000']])
})

test('a drag the system cancels stops following the pointer and keeps the width reached', () => {
  // Arrange
  loadHandout()
  const store = memoryStore()
  startHandout(document, store)
  const edge = document.querySelector<HTMLElement>('.edge.right')
  const panel = document.querySelector<HTMLElement>('.panel')
  edge?.dispatchEvent(new PointerEvent('pointerdown', { clientX: 450, pointerId: 1 }))
  edge?.dispatchEvent(new PointerEvent('pointermove', { clientX: 500, pointerId: 1 }))

  // Act
  edge?.dispatchEvent(new PointerEvent('pointercancel', { pointerId: 1 }))
  edge?.dispatchEvent(new PointerEvent('pointermove', { clientX: 400, pointerId: 1 }))

  // Assert
  expect(panel?.style.width).toBe('1000px')
  expect([...store.values]).toEqual([[`dw-handout-width:${location.pathname}`, '1000']])
})

test('the remembered width comes back when the same file is opened again', () => {
  // Arrange
  loadHandout()
  const store = memoryStore({ [`dw-handout-width:${location.pathname}`]: '700' })

  // Act
  startHandout(document, store)

  // Assert
  expect(document.querySelector<HTMLElement>('.panel')?.style.width).toBe('700px')
})

test('on a narrow window the panel never gets wider than the window allows', () => {
  // Arrange
  Object.defineProperty(window, 'innerWidth', { configurable: true, value: 400 })
  loadHandout()
  const store = memoryStore({ [`dw-handout-width:${location.pathname}`]: '900' })

  // Act
  startHandout(document, store)

  // Assert
  expect(document.querySelector<HTMLElement>('.panel')?.style.width).toBe('368px')
})

test('a double-click on an edge brings the panel back to its default width and forgets the drag', () => {
  // Arrange
  loadHandout()
  const store = memoryStore({ [`dw-handout-width:${location.pathname}`]: '700' })
  startHandout(document, store)

  // Act
  document.querySelector<HTMLElement>('.edge.left')?.dispatchEvent(new MouseEvent('dblclick'))

  // Assert
  expect(document.querySelector<HTMLElement>('.panel')?.style.width).toBe('')
  expect(store.values.size).toBe(0)
})

test('an element of a page that shares the page class is not counted as a page of its own', () => {
  // Arrange
  loadHandout(
    PAGES.map((page) =>
      page.n === 1 ? { ...page, html: `${page.html}<div class="page">引用</div>` } : page,
    ),
  )

  // Act
  startHandout(document, memoryStore())

  // Assert
  expect(headerText()).toBe('1/3 【準備】書き出しの流れ')
})

test('the button under a page hands the keyboard focus to the reading area of the page it opens', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const next = document.querySelector<HTMLButtonElement>('#page-1 .pager .next')

  // Act
  next?.focus()
  next?.click()

  // Assert
  expect(document.activeElement).toBe(document.querySelector('.scroller'))
  expect(visiblePages()).toEqual(['page-2'])
})

test('a screen reader hears the page number and title each time the page changes', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())

  // Act
  press('ArrowRight')

  // Assert
  const announcer = document.querySelector('[aria-live="polite"]')
  expect(announcer?.textContent).toBe('2/3 【仕組み】判定の仕組み')
})

test('Esc closes the table of contents and gives the focus back to its button', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const tocButton = document.querySelector<HTMLButtonElement>('.header .btn[aria-label="目次"]')
  tocButton?.click()
  document.querySelector<HTMLButtonElement>('.toc button')?.focus()

  // Act
  press('Escape')

  // Assert
  expect(document.querySelector<HTMLElement>('.toc')?.hidden).toBe(true)
  expect(document.activeElement).toBe(tocButton)
})

test('arrow keys typed in a field or inside a code block stay there and do not turn the page', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const field = document.createElement('input')
  document.querySelector('#page-1')?.append(field)
  const code = document.querySelector<HTMLElement>('#page-1 pre')

  // Act
  field.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))
  code?.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))

  // Assert
  expect(visiblePages()).toEqual(['page-1'])
})

test('each diagram has its own enlarge button, which says whether the diagram is enlarged; the diagram stays readable', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const holder = document.querySelector<HTMLElement>('#page-2 .diagram')
  const button = holder?.querySelector<HTMLButtonElement>('button.diagram-toggle')

  // Act
  button?.click()
  const afterClick = {
    wide: holder?.classList.contains('wide'),
    pressed: button?.getAttribute('aria-pressed'),
  }
  button?.click()

  // Assert
  expect(holder?.hasAttribute('role')).toBe(false)
  expect(holder?.hasAttribute('aria-label')).toBe(false)
  expect(button?.type).toBe('button')
  expect(afterClick).toEqual({ wide: true, pressed: 'true' })
  expect(holder?.classList.contains('wide')).toBe(false)
  expect(button?.getAttribute('aria-pressed')).toBe('false')
})

test('a browser that refuses to store the dragged width keeps the panel working, the width unremembered', () => {
  // Arrange
  loadHandout()
  const refusing: WidthStore = {
    getItem: () => {
      throw new Error('SecurityError')
    },
    setItem: () => {
      throw new Error('QuotaExceededError')
    },
    removeItem: () => {
      throw new Error('SecurityError')
    },
  }

  // Act
  const start = () => startHandout(document, refusing)
  start()
  const edge = document.querySelector<HTMLElement>('.edge.right')
  const drag = () => {
    edge?.dispatchEvent(new PointerEvent('pointerdown', { clientX: 1050, pointerId: 1, bubbles: true }))
    document.dispatchEvent(new PointerEvent('pointermove', { clientX: 1100, pointerId: 1, bubbles: true }))
    document.dispatchEvent(new PointerEvent('pointerup', { clientX: 1100, pointerId: 1, bubbles: true }))
    edge?.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }))
  }

  // Assert
  expect(drag).not.toThrow()
  expect(document.querySelector('#pageno')?.textContent).toBe('1/3')
})

test('after a click into a code block that scrolls sideways, Tab to a button gives the arrow keys back to paging', () => {
  // Arrange
  loadHandout()
  startHandout(document, memoryStore())
  const code = document.querySelector<HTMLElement>('#page-1 pre')
  // Nothing is laid out here: the block is made wider than its box by hand
  if (code) {
    Object.defineProperty(code, 'scrollWidth', { value: 900 })
    Object.defineProperty(code, 'clientWidth', { value: 300 })
  }
  code?.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }))
  press('ArrowRight')
  const whileInBlock = visiblePages()

  // Act
  document.querySelector<HTMLButtonElement>('.header .btn[aria-label="目次"]')?.focus()
  press('ArrowRight')

  // Assert
  expect(whileInBlock).toEqual(['page-1'])
  expect(visiblePages()).toEqual(['page-2'])
})

test('each diagram’s enlarge button comes before the drawing, on a line of its own: it never covers a label', () => {
  // Arrange
  loadHandout()

  // Act
  startHandout(document, memoryStore())

  // Assert
  const holders = Array.from(document.querySelectorAll<HTMLElement>('.diagram'))
  expect(holders.length).toBeGreaterThan(0)
  expect(holders.map((holder) => holder.firstElementChild?.className)).toEqual(
    holders.map(() => 'diagram-toggle'),
  )
})

// Generated by the /gstack-ship test coverage audit (pass 1).
// Value: protects=a shared link to a page the Handout lacks, or to no page, opens a real page and rewrites the address to it; fails_when=show() stops clamping or pageFromHash takes a non-number; why_new=the existing specs open only #2, #3 and valid hashes; seam=none; no_claim=the browser's scroll to an in-page anchor (happy-dom stands in)
test('a shared link past the last page opens the last page, and a link that is no page number opens page 1', () => {
  // Arrange
  loadHandout()
  history.replaceState(null, '', '#99')

  // Act
  startHandout(document, memoryStore())
  const afterPastEnd = { visible: visiblePages(), hash: location.hash }
  document.body.innerHTML = ''
  loadHandout()
  history.replaceState(null, '', '#settings')
  startHandout(document, memoryStore())

  // Assert
  expect(afterPastEnd).toEqual({ visible: ['page-3'], hash: '#3' })
  expect(visiblePages()).toEqual(['page-1'])
  expect(location.hash).toBe('#1')
})
