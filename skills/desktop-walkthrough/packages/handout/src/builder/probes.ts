/**
 * The probes: code the host runs inside its page view on the builder's behalf (contract `probe`).
 *
 * Why they live here: the page view holds the rendered page, the builder holds the policy. A probe
 * reports facts (boxes, texts, the controller's state) and the builder judges them, so the judging
 * code stays in tested TypeScript. A probe is sent as source text (`probeBody`): it must not use
 * anything from this module's scope, only its argument and the page's globals.
 */
import { z } from 'zod'

/** One diagram label as the page laid it out: its text, its box, and the box of what it holds. */
export const labelBoxSchema = z.object({
  text: z.string(),
  width: z.number(),
  height: z.number(),
  /** The label's content (a foreignObject's HTML); the box itself for an SVG `<text>`. */
  contentWidth: z.number(),
  contentHeight: z.number(),
})
export type LabelBox = z.infer<typeof labelBoxSchema>

/** What {@link measurePage} reports for one rendered page. */
export const pageMeasurementSchema = z.object({
  /** `#content` after rendering, every `<details>` back in the state the author left it. */
  html: z.string(),
  diagrams: z.array(z.object({ id: z.string(), labels: z.array(labelBoxSchema) })),
})
export type PageMeasurement = z.infer<typeof pageMeasurementSchema>

/** Arguments of {@link measurePage}. */
export interface MeasureArgs {
  contentId: string
}

/**
 * Probe run after a page reported: open every `<details>`, measure each diagram label, close them
 * again and take the content. Closed details lay nothing out, so their labels would measure 0 (DX D9).
 *
 * @param args - Where the content is.
 * @returns A {@link PageMeasurement}, parsed by the builder.
 *
 * @example
 * await measurePage({ contentId: 'content' }) // { html: '<h1>…</h1>…', diagrams: [{ id: 'p2-d1', labels: [{ text: '書き出す', width: 70, … }] }] }
 */
export async function measurePage(args: MeasureArgs): Promise<unknown> {
  const content = document.getElementById(args.contentId)
  if (!content) return { html: '', diagrams: [] }
  const closed = Array.from(content.querySelectorAll('details')).filter((details) => !details.open)
  for (const details of closed) details.open = true
  // Two frames: the opened details lay out before anything is measured
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
  const diagrams = Array.from(content.querySelectorAll('.diagram')).map((holder) => {
    const svg = holder.querySelector('svg')
    const labels = svg
      ? Array.from(svg.querySelectorAll('foreignObject, text')).map((label) => {
          const box = label.getBoundingClientRect()
          // A foreignObject's HTML can lay out past its box; an SVG text is its own box
          const inner = label.localName === 'foreignObject' ? label.firstElementChild : null
          const innerBox = inner ? inner.getBoundingClientRect() : box
          return {
            text: (label.textContent ?? '').trim(),
            width: box.width,
            height: box.height,
            contentWidth: innerBox.width,
            contentHeight: innerBox.height,
          }
        })
      : []
    return { id: svg ? svg.id : '', labels }
  })
  for (const details of closed) details.open = false
  return { html: content.innerHTML, diagrams }
}

/** What {@link checkHandout} reports for the reopened Handout. */
export const handoutCheckSchema = z.object({
  /** The controller marked the document as taken over. */
  ready: z.boolean(),
  pages: z.number(),
  /** The header's `N/M` as shown. */
  pageNumber: z.string(),
  /** Whether page 2 showed after `#2`; null when there is no page 2 or the controller never took over. */
  secondShown: z.boolean().nullable(),
  diagrams: z.array(z.object({ id: z.string(), labels: z.array(z.string()) })),
  /** Embedded pictures the browser could not decode: the page's number (`data-n`) and the picture's position on it, from 1. */
  brokenImages: z.array(z.object({ page: z.number(), image: z.number() })),
})
export type HandoutCheck = z.infer<typeof handoutCheckSchema>

/** Arguments of {@link checkHandout}: the names of HANDOUT_DOM and the waits. */
export interface CheckArgs {
  readyAttribute: string
  pageClass: string
  /** The holder of the pages: only its own article children are pages, never an element inside one. */
  pagesId: string
  pageIdPrefix: string
  pageNumberId: string
  readyLimitMs: number
  pollMs: number
  hashChangeLimitMs: number
  /** How long one picture may take to decode before it counts as broken. */
  imageDecodeLimitMs: number
  /** How many pictures decode at once. */
  imageDecodeConcurrency: number
}

/**
 * Probe run in the finished Handout, opened under its own CSP (eng D10): did the controller take
 * over, does `#2` open page 2, which label texts does each diagram carry after sanitizing, and
 * which embedded pictures does the browser fail to decode (a cut-off screenshot passes every check
 * of its bytes but shows as a broken image).
 *
 * @param args - The names the controller uses and how long to wait for it and for each picture.
 * @returns A {@link HandoutCheck}, compared by the builder with what it measured before sanitizing.
 *
 * @example
 * await checkHandout({ readyAttribute: 'data-handout-ready', … })
 * // { ready: true, pages: 3, pageNumber: '1/3', secondShown: true, diagrams: [{ id: 'p2-d1', labels: ['書き出す', …] }], brokenImages: [] }
 */
export async function checkHandout(args: CheckArgs): Promise<unknown> {
  const root = document.documentElement
  const started = Date.now()
  while (!root.hasAttribute(args.readyAttribute) && Date.now() - started < args.readyLimitMs) {
    await new Promise((resolve) => setTimeout(resolve, args.pollMs))
  }
  const ready = root.hasAttribute(args.readyAttribute)
  const pages = document.querySelectorAll(`#${args.pagesId} > article.${args.pageClass}`).length
  const pageNumber = (document.getElementById(args.pageNumberId)?.textContent ?? '').trim()
  let secondShown: boolean | null = null
  if (ready && pages >= 2) {
    // The controller's own hashchange listener runs first; this one reads the result after it
    const changed = new Promise((resolve) => {
      addEventListener('hashchange', () => setTimeout(resolve, 0), { once: true })
      setTimeout(resolve, args.hashChangeLimitMs)
    })
    location.hash = '#2'
    await changed
    const second = document.getElementById(`${args.pageIdPrefix}2`)
    secondShown = Boolean(second && !second.hidden)
  }
  const diagrams = Array.from(document.querySelectorAll('.diagram svg')).map((svg) => ({
    id: svg.id,
    labels: Array.from(svg.querySelectorAll('foreignObject, text'))
      .map((label) => (label.textContent ?? '').trim())
      .filter((text) => text !== ''),
  }))
  // Every picture is decoded on its own, so a hidden page's pictures are checked too: each distinct
  // source once (a picture shown on several pages), a few at a time, then every place it shows
  const places: Array<{ page: number; image: number; source: string }> = []
  for (const article of Array.from(
    document.querySelectorAll(`#${args.pagesId} > article.${args.pageClass}`),
  )) {
    const pictures = Array.from(article.querySelectorAll('img, svg image'))
    for (const [index, picture] of pictures.entries()) {
      const source =
        picture.getAttribute('src') ??
        picture.getAttribute('href') ??
        picture.getAttribute('xlink:href') ??
        ''
      places.push({ page: Number(article.getAttribute('data-n')), image: index + 1, source })
    }
  }
  const sources = Array.from(new Set(places.map((place) => place.source)))
  const decodedSources = new Map<string, boolean>()
  let next = 0
  const decodeNext = async (): Promise<void> => {
    while (next < sources.length) {
      const source = sources[next] ?? ''
      next += 1
      const probe = new Image()
      probe.src = source
      const decoded = await Promise.race([
        probe.decode().then(
          () => true,
          () => false,
        ),
        new Promise<boolean>((resolve) => setTimeout(() => resolve(false), args.imageDecodeLimitMs)),
      ])
      decodedSources.set(source, decoded)
    }
  }
  await Promise.all(Array.from({ length: Math.min(args.imageDecodeConcurrency, sources.length) }, decodeNext))
  const brokenImages = places
    .filter((place) => decodedSources.get(place.source) !== true)
    .map(({ page, image }) => ({ page, image }))
  return { ready, pages, pageNumber, secondShown, diagrams, brokenImages }
}

/**
 * The source the host evaluates for a probe: the probe's own text, called with its arguments.
 *
 * @param probe - {@link measurePage} or {@link checkHandout}.
 * @param args - Its argument, passed as JSON.
 * @returns The body of an async function, as the contract's `probe` field takes it.
 *
 * @example
 * probeBody(measurePage, { contentId: 'content' }) // 'return await (async function measurePage(args) {…})({"contentId":"content"})'
 */
export function probeBody<Args>(probe: (args: Args) => Promise<unknown>, args: Args): string {
  return `return await (${probe.toString()})(${JSON.stringify(args)})`
}
