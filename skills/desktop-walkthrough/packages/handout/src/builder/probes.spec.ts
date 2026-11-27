import { afterEach, expect, test, vi } from 'vitest'

import { checkHandout, handoutCheckSchema, measurePage, pageMeasurementSchema, probeBody } from './probes'

/** The constructor of async functions: how the host's callAsyncJavaScript runs a probe's source. */
const AsyncFunction = Object.getPrototypeOf(async () => undefined).constructor as new (
  body: string,
) => () => Promise<unknown>

const checkArgs = {
  readyAttribute: 'data-handout-ready',
  pageClass: 'page',
  pagesId: 'handout-pages',
  pageIdPrefix: 'page-',
  pageNumberId: 'pageno',
  readyLimitMs: 500,
  pollMs: 10,
  hashChangeLimitMs: 200,
  imageDecodeLimitMs: 200,
  imageDecodeConcurrency: 2,
}

/** Lay out a label only while every <details> around it is open, as WebKit does. */
function layOutOpenDetailsOnly(): void {
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
    const shown = !this.closest('details:not([open])')
    return new DOMRect(0, 0, shown ? 70 : 0, shown ? 24 : 0)
  })
}

/** Show page n the way the Handout's controller does: the others hidden, the header counting. */
function showPage(n: number): void {
  for (const page of document.querySelectorAll<HTMLElement>('.page')) page.hidden = page.id !== `page-${n}`
  const pageNumber = document.getElementById('pageno')
  if (pageNumber) pageNumber.textContent = `${n}/2`
}

afterEach(() => {
  vi.restoreAllMocks()
  document.body.innerHTML = ''
  document.documentElement.removeAttribute('data-handout-ready')
  history.replaceState(null, '', '#')
})

test('labels inside a closed <details> are measured open, and the details close again', async () => {
  // Arrange
  document.body.innerHTML =
    '<main id="content"><details><summary>図</summary><div class="diagram"><svg id="p1-d1">' +
    '<foreignObject width="70" height="24"><div>書き出す</div></foreignObject></svg></div></details></main>'
  layOutOpenDetailsOnly()

  // Act
  const measurement = pageMeasurementSchema.parse(await measurePage({ contentId: 'content' }))

  // Assert
  expect(measurement.diagrams).toEqual([
    {
      id: 'p1-d1',
      labels: [{ text: '書き出す', width: 70, height: 24, contentWidth: 70, contentHeight: 24 }],
    },
  ])
  expect(measurement.html).toContain('<details><summary>図</summary>')
})

test('a details block the author left open stays open in the Handout', async () => {
  // Arrange
  document.body.innerHTML =
    '<main id="content"><details open=""><summary>例</summary><p>本文</p></details></main>'

  // Act
  const measurement = pageMeasurementSchema.parse(await measurePage({ contentId: 'content' }))

  // Assert
  expect(measurement.html).toBe('<details open=""><summary>例</summary><p>本文</p></details>')
})

test('the measuring probe runs from its source text alone, as the host evaluates it', async () => {
  // Arrange
  document.body.innerHTML =
    '<main id="content"><div class="diagram"><svg id="p2-d1"><text>画面</text></svg></div></main>'
  layOutOpenDetailsOnly()
  const body = probeBody(measurePage, { contentId: 'content' })

  // Act
  const fromSource = await new AsyncFunction(body)()

  // Assert
  expect(fromSource).toEqual(await measurePage({ contentId: 'content' }))
})

test('the verify probe sees the controller take over and open page 2 for #2', async () => {
  // Arrange
  document.body.innerHTML =
    '<span id="pageno"></span><main id="handout-pages"><article class="page" id="page-1"></article><article class="page" id="page-2" hidden></article></main>' +
    '<div class="diagram"><svg id="p2-d1"><foreignObject><div>書き出す</div></foreignObject><text></text></svg></div>'
  addEventListener('hashchange', () => showPage(Number(location.hash.slice(1))), { once: true })
  setTimeout(() => {
    showPage(1)
    document.documentElement.setAttribute('data-handout-ready', '')
  }, 30)

  // Act
  const check = handoutCheckSchema.parse(await new AsyncFunction(probeBody(checkHandout, checkArgs))())

  // Assert
  expect(check).toEqual({
    ready: true,
    pages: 2,
    pageNumber: '1/2',
    secondShown: true,
    diagrams: [{ id: 'p2-d1', labels: ['書き出す'] }],
    brokenImages: [],
  })
})

test('the verify probe reports a controller that never took over, without paging', async () => {
  // Arrange
  document.body.innerHTML =
    '<main id="handout-pages"><article class="page" id="page-1"></article><article class="page" id="page-2"></article></main>'

  // Act
  const check = handoutCheckSchema.parse(await checkHandout(checkArgs))

  // Assert
  expect(check).toEqual({
    ready: false,
    pages: 2,
    pageNumber: '',
    secondShown: null,
    diagrams: [],
    brokenImages: [],
  })
})

test("the verify probe counts the Handout's pages only, not a page's element that shares their class", async () => {
  // Arrange
  document.body.innerHTML =
    '<main id="handout-pages"><article class="page" id="page-1"><div class="page">引用</div></article></main>'

  // Act
  const check = handoutCheckSchema.parse(await checkHandout(checkArgs))

  // Assert
  expect(check.pages).toBe(1)
})

/** Decode a picture the way WebKit does for these specs: a source holding "broken" fails, any other succeeds. */
function decodeUnlessBroken(): void {
  vi.spyOn(HTMLImageElement.prototype, 'decode').mockImplementation(function (this: HTMLImageElement) {
    return this.src.includes('broken') ? Promise.reject(new Error('EncodingError')) : Promise.resolve()
  })
}

test('the verify probe names each embedded picture the browser cannot decode, by page and position', async () => {
  // Arrange
  decodeUnlessBroken()
  document.body.innerHTML =
    '<main id="handout-pages">' +
    '<article class="page" id="page-1" data-n="2"><img src="data:image/png;base64,ok"><img src="data:image/png;base64,broken"></article>' +
    '<article class="page" id="page-2" data-n="5"><svg><image href="data:image/png;base64,broken"></image></svg></article>' +
    '</main>'

  // Act
  const check = handoutCheckSchema.parse(await checkHandout(checkArgs))

  // Assert
  expect(check.brokenImages).toEqual([
    { page: 2, image: 2 },
    { page: 5, image: 1 },
  ])
})

test('a picture shown on several pages is decoded once, and each place it shows is reported when it is broken', async () => {
  // Arrange
  decodeUnlessBroken()
  document.body.innerHTML =
    '<main id="handout-pages">' +
    '<article class="page" id="page-1" data-n="1"><img src="data:image/png;base64,broken"><img src="data:image/png;base64,ok"></article>' +
    '<article class="page" id="page-2" data-n="2"><img src="data:image/png;base64,broken"></article>' +
    '</main>'

  // Act
  const check = handoutCheckSchema.parse(await checkHandout(checkArgs))

  // Assert
  expect(HTMLImageElement.prototype.decode).toHaveBeenCalledTimes(2)
  expect(check.brokenImages).toEqual([
    { page: 1, image: 1 },
    { page: 2, image: 1 },
  ])
})
