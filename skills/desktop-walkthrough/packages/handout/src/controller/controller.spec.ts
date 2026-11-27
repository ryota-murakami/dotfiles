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
function loadHandout(): void {
  const html = assembleHandout({
    pages: PAGES,
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
