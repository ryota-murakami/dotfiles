import { findSecrets, maskSecrets } from '../../../../hooks/secrets'
import type { Diagnostic, HandoutPage } from '../contract'
import { decodeBase64 } from '../utils/decodeBase64'
import { excerpt } from '../utils/excerpt'
import { resolvePath } from '../utils/resolvePath'
import type { ImageMime } from '../utils/sniffImage'
import { sniffImage } from '../utils/sniffImage'
import type { HostPort } from './host'
import { readFile } from './host'

/** The file extensions a Handout embeds; what an image's bytes are decides its type ({@link sniffImage}). */
const IMAGE_EXTENSIONS: ReadonlySet<string> = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'svg'])

/** Where an `<img>` source points: an embedded image to keep, a local file to read, or something refused. */
type ImageSource = { kind: 'embedded' } | { kind: 'file'; path: string } | { kind: 'refused'; reason: string }

/**
 * Classify an image source as written in the page (DX D15): absolute paths and `file:` links as
 * they are, relative paths against the Record's `pages/` folder, `data:image/` kept, anything else
 * (the network) refused, since the Handout loads nothing from outside itself.
 *
 * @param source - The `src` attribute.
 * @param pagesDir - The Record's `pages/` folder.
 * @returns Where the image comes from.
 *
 * @example
 * classifySource('shot.png', '/r/pages')                 // { kind: 'file', path: '/r/pages/shot.png' }
 * classifySource('https://cdn.test/a.png', '/r/pages')   // { kind: 'refused', reason: 'is not a local file' }
 * classifySource('shot%zz.png', '/r/pages')              // { kind: 'refused', reason: 'has a malformed %-escape in its path' }
 */
export function classifySource(source: string, pagesDir: string): ImageSource {
  if (/^data:image\//i.test(source)) return { kind: 'embedded' }
  // A "%" that starts no escape (shot%zz.png) names no file: refused with a reason, never thrown
  try {
    if (/^file:\/\//i.test(source))
      return { kind: 'file', path: decodeURIComponent(new URL(source).pathname) }
    if (/^[a-z][a-z0-9+.-]*:/i.test(source) || source.startsWith('//'))
      return { kind: 'refused', reason: 'is not a local file' }
    const path = decodeURIComponent(source.replace(/[?#].*$/, ''))
    return { kind: 'file', path: path.startsWith('/') ? path : resolvePath(pagesDir, path) }
  } catch {
    return { kind: 'refused', reason: 'has a malformed %-escape in its path' }
  }
}

/**
 * Embed every local image of a rendered page as a `data:` URI, so the Handout works as one file (DX D15).
 *
 * Why it exists: the colleague receives the HTML file alone; a path on this Mac means nothing on
 * theirs. An image that cannot be embedded stops the export (HANDOUT_IMAGE) with the line where the
 * page names it, rather than shipping a broken picture. Every picture's bytes must be an image (a
 * file named shot.png can hold anything), and an SVG's text must hold no secret shape
 * (HANDOUT_SECRET), whether it is read from a file or written into the page as data. Both `<img>`
 * and the `<image>` of an inline SVG are embedded. Called by {@link buildHandout} per page.
 *
 * @param page - The page as dw listed it (its source gives the line of each image).
 * @param html - The page's rendered content.
 * @param recordDir - The Record's folder.
 * @param host - Reads the files.
 * @returns The content with images embedded, and one diagnostic per image that could not be.
 *
 * @example
 * await embedImages(page, '<p><img src="shot.png" alt="画面"></p>', '/r', host)
 * // { html: '<p><img src="data:image/png;base64,iVBOR…" alt="画面"></p>', diagnostics: [] }
 */
export async function embedImages(
  page: HandoutPage,
  html: string,
  recordDir: string,
  host: HostPort,
): Promise<{ html: string; diagnostics: Diagnostic[] }> {
  const holder = document.createElement('template')
  holder.innerHTML = html
  // An <img>, and an <image> an inline SVG draws: the finished file's CSP shows neither from a path
  const images = Array.from(holder.content.querySelectorAll('img, svg image'))
  // Nothing to embed: the content goes on exactly as rendered
  if (images.length === 0) return { html, diagnostics: [] }
  const sourceLines = page.markdown.split('\n')
  const diagnostics: Diagnostic[] = []
  for (const image of images) {
    // An <img> names its picture in src; an SVG <image> in href (xlink:href in older drawings)
    const attribute = image.localName === 'img' ? 'src' : image.hasAttribute('href') ? 'href' : 'xlink:href'
    const source = image.getAttribute(attribute) ?? ''
    const failure = await embedOne(image, attribute, classifySource(source, `${recordDir}/pages`), host)
    if (failure === null) continue
    const index = imageLine(sourceLines, source)
    const where = index < 0 ? maskSecrets(page.source) : `${maskSecrets(page.source)}:${index + 1}`
    diagnostics.push({
      code: failure.code,
      message: `${where}: the image ${excerpt(maskSecrets(source || '(no src)'))} ${failure.reason}`,
      page: page.n,
      ...(index < 0 ? {} : { line: index + 1 }),
    })
  }
  return { html: holder.innerHTML, diagnostics }
}

/**
 * The line of a page's source that names an image, from 0: where it is written as an image
 * (`](src`, `src="src"`), else any line holding the text. A short source (`x`) would otherwise point
 * at the first line that happens to contain its letters.
 *
 * @param lines - The page's original source, split into lines.
 * @param source - The image's `src` as rendered.
 * @returns The index of the line, or -1 when no line names it.
 *
 * @example
 * imageLine(['export x', '<img src="x">'], 'x') // 1
 * imageLine(['![画面](shot.png)'], 'shot.png')  // 0
 */
function imageLine(lines: readonly string[], source: string): number {
  if (source === '') return -1
  const written = [`](${source}`, `src="${source}"`, `src='${source}'`, `src=${source}`]
  const asImage = lines.findIndex((text) => written.some((form) => text.includes(form)))
  return asImage >= 0 ? asImage : lines.findIndex((text) => text.includes(source))
}

/** Why an image is not embedded, worded to follow "the image X", and the code it stops the export with. */
interface EmbedFailure {
  code: Extract<Diagnostic['code'], 'HANDOUT_IMAGE' | 'HANDOUT_SECRET'>
  reason: string
}

/**
 * Put one image's bytes into its source attribute, once they proved to be an image.
 *
 * @param image - The `<img>` or SVG `<image>`.
 * @param attribute - Where it names its picture: `src`, `href` or `xlink:href`.
 * @param source - Where that picture is, as {@link classifySource} read it.
 * @param host - Reads the files.
 * @returns
 * - null when the picture is embedded (or was written into the page as data and checks out)
 * - an {@link EmbedFailure} otherwise
 *
 * @example
 * await embedOne(image, 'src', { kind: 'file', path: '/r/pages/shot.png' }, host) // null; src is data:image/png;base64,…
 * await embedOne(image, 'src', { kind: 'refused', reason: 'is not a local file' }, host) // { code: 'HANDOUT_IMAGE', reason: 'is not a local file' }
 */
async function embedOne(
  image: Element,
  attribute: string,
  source: ImageSource,
  host: HostPort,
): Promise<EmbedFailure | null> {
  if (source.kind === 'refused') return { code: 'HANDOUT_IMAGE', reason: source.reason }
  // Written into the page as data: kept as written, once its bytes check out like a file's
  if (source.kind === 'embedded') {
    const bytes = dataUriBytes(image.getAttribute(attribute) ?? '')
    if (bytes === null)
      return { code: 'HANDOUT_IMAGE', reason: 'is not an image: its data cannot be decoded' }
    const inspected = inspectImage(bytes)
    return inspected.ok ? null : inspected.failure
  }
  const extension = /\.([A-Za-z0-9]+)$/.exec(source.path)?.[1]?.toLowerCase() ?? ''
  if (!IMAGE_EXTENSIONS.has(extension))
    return {
      code: 'HANDOUT_IMAGE',
      reason: 'is not a type the Handout embeds (png, jpg, gif, webp, avif, svg)',
    }
  const read = await readFile(host, source.path)
  if (!read.ok)
    return { code: 'HANDOUT_IMAGE', reason: `could not be read: ${excerpt(maskSecrets(read.message))}` }
  const inspected = inspectImage(decodeBase64(read.base64))
  if (!inspected.ok) return inspected.failure
  // The type the bytes are, not the one the name claims: a JPEG saved as .png still shows
  image.setAttribute(attribute, `data:${inspected.mime};base64,${read.base64}`)
  return null
}

/**
 * Whether some bytes may go into a Handout as an image: what image they are, or why not.
 *
 * @param bytes - A file's contents, or the data written into a page.
 * @returns
 * - `{ ok: true, mime }` for png, jpeg, gif, webp, avif, and svg without a secret shape
 * - `{ ok: false, failure }` for other bytes (HANDOUT_IMAGE) and an SVG holding a secret shape (HANDOUT_SECRET)
 *
 * @example
 * inspectImage(new TextEncoder().encode('{"error":"expired"}')) // { ok: false, failure: { code: 'HANDOUT_IMAGE', reason: 'is not an image: …' } }
 */
function inspectImage(
  bytes: Uint8Array,
): { ok: true; mime: ImageMime } | { ok: false; failure: EmbedFailure } {
  const mime = sniffImage(bytes)
  if (mime === null) {
    return {
      ok: false,
      failure: {
        code: 'HANDOUT_IMAGE',
        reason: 'is not an image: its bytes are not png, jpeg, gif, webp, avif or svg',
      },
    }
  }
  // An SVG is text: a signed link in its metadata or one of its URLs would travel with the picture
  if (mime === 'image/svg+xml') {
    const [finding] = findSecrets(new TextDecoder().decode(bytes))
    if (finding) {
      return {
        ok: false,
        failure: {
          code: 'HANDOUT_SECRET',
          reason: `carries a secret shape (${finding.pattern}); remove the value from the file`,
        },
      }
    }
  }
  return { ok: true, mime }
}

/**
 * The bytes a `data:image/…` source holds: base64 decoded, or the URL-encoded text as UTF-8.
 *
 * @param source - The source as written in the page.
 * @returns The bytes, or null when they cannot be decoded.
 *
 * @example
 * dataUriBytes('data:image/svg+xml,%3Csvg%3E') // the bytes of '<svg>'
 * dataUriBytes('data:image/png;base64,@@')     // null
 */
function dataUriBytes(source: string): Uint8Array | null {
  const comma = source.indexOf(',')
  if (comma < 0) return null
  const header = source.slice(0, comma)
  const payload = source.slice(comma + 1)
  try {
    return /;base64$/i.test(header)
      ? decodeBase64(payload.replace(/\s/g, ''))
      : new TextEncoder().encode(decodeURIComponent(payload))
  } catch {
    return null
  }
}
