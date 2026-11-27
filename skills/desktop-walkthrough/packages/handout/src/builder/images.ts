import { findSecrets, maskSecrets } from '../../../../hooks/secrets'
import { IMAGE_LIMIT_BYTES, IMAGE_TOTAL_LIMIT_BYTES, NESTED_PICTURE_DEPTH } from '../constants'
import type { Diagnostic, HandoutPage } from '../contract'
import { base64DecodedLength } from '../utils/base64DecodedLength'
import { byteTexts } from '../utils/byteTexts'
import { collectReadableText } from '../utils/collectReadableText'
import { decodeBase64 } from '../utils/decodeBase64'
import { decodeXmlEntities } from '../utils/decodeXmlEntities'
import { encodeBase64 } from '../utils/encodeBase64'
import { excerpt } from '../utils/excerpt'
import { inflateLimited } from '../utils/inflateLimited'
import { gifExtensionTexts } from '../utils/gifExtensionTexts'
import { pngChunks } from '../utils/pngChunks'
import { pngCompressedTexts } from '../utils/pngCompressedTexts'
import { resolvePath } from '../utils/resolvePath'
import type { ImageMime } from '../utils/sniffImage'
import { sniffImage } from '../utils/sniffImage'
import type { HostPort } from './host'
import { readFile } from './host'
import { decodeTextByBom } from '../utils/decodeTextByBom'
import { percentDecode } from '../utils/percentDecode'

/** Where an image source points: an embedded image to keep, a local file to read, or something refused. */
type ImageSource = { kind: 'embedded' } | { kind: 'file'; path: string } | { kind: 'refused'; reason: string }

/** Why an image is not embedded, worded to follow "the image X", and the code it stops the export with. */
interface EmbedFailure {
  code: Extract<Diagnostic['code'], 'HANDOUT_IMAGE' | 'HANDOUT_SECRET'>
  reason: string
}

/** A picture whose bytes passed every check, ready to embed. */
interface CheckedImage {
  mime: ImageMime
  base64: string
  /** Its size in bytes, before base64. */
  size: number
}

/** What reading and checking one source came to: the picture, or why it is not embedded. */
type CheckOutcome = { ok: true; image: CheckedImage } | { ok: false; failure: EmbedFailure }

/** What to do about a secret shape in a raster picture's metadata. */
const METADATA_ADVICE = 'save the picture again without it'

/**
 * What one export's pictures have cost so far, shared by every page of it: each file read and
 * checked once (a picture shown on several pages), and the bytes embedded, against a total. Once
 * the total is passed no further file is read: the export stops anyway, and memory stays bounded.
 */
export interface ImageLedger {
  /** Path → the outcome of reading and checking that file. */
  readonly checked: Map<string, Promise<CheckOutcome>>
  /** The most picture bytes the Handout embeds in all. */
  readonly totalLimitBytes: number
  /** Bytes embedded so far; a picture shown twice is in the file twice and counts twice. */
  embeddedBytes: number
  /** Whether a picture already passed the total. */
  exhausted: boolean
  /** Raster pictures embedded (png, jpeg, gif, webp, avif): what they show is no text any check reads. */
  rasterPictures: number
}

/**
 * A fresh ledger for one export, created by {@link buildHandout} and handed to {@link embedImages}
 * for every page.
 *
 * @param totalLimitBytes - The most picture bytes the Handout may embed in all.
 * @returns A ledger with nothing read and nothing embedded.
 *
 * @example
 * createImageLedger() // { checked: Map {}, totalLimitBytes: 104857600, embeddedBytes: 0, exhausted: false, rasterPictures: 0 }
 */
export function createImageLedger(totalLimitBytes: number = IMAGE_TOTAL_LIMIT_BYTES): ImageLedger {
  return { checked: new Map(), totalLimitBytes, embeddedBytes: 0, exhausted: false, rasterPictures: 0 }
}

/**
 * Classify an image source as written in the page (DX D15): absolute paths and `file:` links as
 * they are, relative paths against the Record's `pages/` folder, `data:image/` kept, anything else
 * (the network, a `file:` link to another computer) refused, since the Handout loads nothing from
 * outside itself.
 *
 * @param source - The `src` (or SVG `href`) attribute.
 * @param pagesDir - The Record's `pages/` folder.
 * @returns Where the image comes from.
 *
 * @example
 * classifySource('shot.png', '/r/pages')                       // { kind: 'file', path: '/r/pages/shot.png' }
 * classifySource('https://cdn.test/a.png', '/r/pages')         // { kind: 'refused', reason: 'is not a local file' }
 * classifySource('file://fileserver/share/a.png', '/r/pages')  // { kind: 'refused', reason: 'names a file on another computer: …' }
 * classifySource('shot%zz.png', '/r/pages')                    // { kind: 'refused', reason: 'has a malformed %-escape in its path' }
 */
export function classifySource(source: string, pagesDir: string): ImageSource {
  if (/^data:image\//i.test(source)) return { kind: 'embedded' }
  // A "%" that starts no escape (shot%zz.png) names no file: refused with a reason, never thrown
  try {
    // file:///Users/… and file:/Users/… alike
    if (/^file:/i.test(source)) {
      const url = new URL(source)
      // file://fileserver/share/a.png is another computer's file: the same path here is another picture
      if (url.host !== '' && url.host !== 'localhost') {
        return {
          kind: 'refused',
          reason: 'names a file on another computer: copy the picture to this Mac and point at it there',
        }
      }
      return { kind: 'file', path: decodeURIComponent(url.pathname) }
    }
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
 * page names it, rather than shipping a broken picture. What a picture's bytes are decides whether
 * it is one, whatever its name (a file named shot.png can hold anything, and capture.bin can be a
 * PNG). Its text must hold no secret shape (HANDOUT_SECRET): an SVG's as an XML reader decodes it,
 * a raster picture's metadata as it is stored. Both `<img>` and the `<image>` of an inline SVG are
 * embedded, each attribute that names a picture. Called by {@link buildHandout} per page, with one
 * ledger for the whole export.
 *
 * @param page - The page as dw listed it (its source gives the line of each image).
 * @param html - The page's rendered content.
 * @param recordDir - The Record's folder.
 * @param host - Reads the files.
 * @param ledger - What the export's pictures have cost so far ({@link createImageLedger}).
 * @returns The content with images embedded, and one diagnostic per image that could not be.
 *
 * @example
 * await embedImages(page, '<p><img src="shot.png" alt="画面"></p>', '/r', host, createImageLedger())
 * // { html: '<p><img src="data:image/png;base64,iVBOR…" alt="画面"></p>', diagnostics: [] }
 */
export async function embedImages(
  page: HandoutPage,
  html: string,
  recordDir: string,
  host: HostPort,
  ledger: ImageLedger,
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
    // An <img> names its picture in src; an SVG <image> in href, xlink:href in older drawings, or both
    const attributes =
      image.localName === 'img' ? ['src'] : ['href', 'xlink:href'].filter((name) => image.hasAttribute(name))
    for (const attribute of attributes.length > 0 ? attributes : ['href']) {
      const source = image.getAttribute(attribute) ?? ''
      const failure = await embedOne(
        image,
        attribute,
        classifySource(source, `${recordDir}/pages`),
        host,
        ledger,
      )
      if (failure === null) continue
      const index = imageLine(sourceLines, source)
      const where = index < 0 ? `page ${page.n}` : `page ${page.n}:${index + 1}`
      diagnostics.push({
        code: failure.code,
        message: `${where}: the image ${excerpt(maskSecrets(source || '(no src)'))} ${failure.reason}`,
        page: page.n,
        ...(index < 0 ? {} : { line: index + 1 }),
      })
    }
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

/**
 * Put one image's bytes into its source attribute, once they proved to be an image without a secret
 * and the export's total allows them.
 *
 * @param image - The `<img>` or SVG `<image>`.
 * @param attribute - Where it names its picture: `src`, `href` or `xlink:href`.
 * @param source - Where that picture is, as {@link classifySource} read it.
 * @param host - Reads the files.
 * @param ledger - The export's files read so far and bytes embedded.
 * @returns
 * - null when the picture is embedded (or was written into the page as data and checks out)
 * - an {@link EmbedFailure} otherwise
 *
 * @example
 * await embedOne(image, 'src', { kind: 'file', path: '/r/pages/shot.png' }, host, ledger) // null; src is data:image/png;base64,…
 * await embedOne(image, 'src', { kind: 'refused', reason: 'is not a local file' }, host, ledger) // { code: 'HANDOUT_IMAGE', reason: 'is not a local file' }
 */
async function embedOne(
  image: Element,
  attribute: string,
  source: ImageSource,
  host: HostPort,
  ledger: ImageLedger,
): Promise<EmbedFailure | null> {
  if (source.kind === 'refused') return { code: 'HANDOUT_IMAGE', reason: source.reason }
  // Past the total, nothing more is read or decoded: the export stops with the pictures already counted
  if (ledger.exhausted) return overTotal(ledger)
  // Written into the page as data: embedded as its checked bytes alone, rebuilt from the type they
  // are, so no other text of the source (a parameter of the data URI) travels unchecked
  if (source.kind === 'embedded') {
    const data = dataUriBytes(image.getAttribute(attribute) ?? '')
    if (!data.ok) return { code: 'HANDOUT_IMAGE', reason: data.reason }
    const inspected = await inspectImage(data.bytes)
    if (!inspected.ok) return inspected.failure
    const overspent = spend(ledger, data.bytes.length)
    if (overspent) return overspent
    if (inspected.mime !== 'image/svg+xml') ledger.rasterPictures += 1
    image.setAttribute(attribute, `data:${inspected.mime};base64,${encodeBase64(data.bytes)}`)
    return null
  }
  // One read and one check per file for the whole export
  let outcome = ledger.checked.get(source.path)
  if (!outcome) {
    outcome = readAndCheck(host, source.path)
    ledger.checked.set(source.path, outcome)
  }
  const checked = await outcome
  if (!checked.ok) return checked.failure
  const overspent = spend(ledger, checked.image.size)
  if (overspent) {
    // Its bytes are of no further use: the export stops
    ledger.checked.delete(source.path)
    return overspent
  }
  if (checked.image.mime !== 'image/svg+xml') ledger.rasterPictures += 1
  // The type the bytes are, not the one the name claims: a JPEG saved as .png still shows
  image.setAttribute(attribute, `data:${checked.image.mime};base64,${checked.image.base64}`)
  return null
}

/**
 * Read a picture's file through the host and check its bytes.
 *
 * @param host - Reads the file.
 * @param path - The file's absolute path.
 * @returns The checked picture, or why it is not embedded.
 *
 * @example
 * await readAndCheck(host, '/r/pages/shot.png') // { ok: true, image: { mime: 'image/png', base64: 'iVBOR…', size: 8 } }
 */
async function readAndCheck(host: HostPort, path: string): Promise<CheckOutcome> {
  const read = await readFile(host, path)
  if (!read.ok)
    return {
      ok: false,
      failure: { code: 'HANDOUT_IMAGE', reason: `could not be read: ${excerpt(maskSecrets(read.message))}` },
    }
  const bytes = decodeBase64(read.base64)
  // The host refuses a larger file before reading it; a host that did not is refused here
  if (bytes.length > IMAGE_LIMIT_BYTES) return { ok: false, failure: tooLarge() }
  const inspected = await inspectImage(bytes)
  if (!inspected.ok) return inspected
  return { ok: true, image: { mime: inspected.mime, base64: read.base64, size: bytes.length } }
}

/**
 * Count a picture's bytes against the export's total.
 *
 * @param ledger - The export's ledger; its `embeddedBytes` grows when the picture fits.
 * @param size - The picture's size in bytes.
 * @returns null when it fits, else the HANDOUT_IMAGE failure that names the total.
 *
 * @example
 * spend(createImageLedger(12), 8) // null
 * spend(ledgerWith8Spent, 8)      // { code: 'HANDOUT_IMAGE', reason: 'would take the pictures of the Handout past 12 bytes in all: …' }
 */
function spend(ledger: ImageLedger, size: number): EmbedFailure | null {
  if (ledger.embeddedBytes + size > ledger.totalLimitBytes) {
    ledger.exhausted = true
    return overTotal(ledger)
  }
  ledger.embeddedBytes += size
  return null
}

/**
 * The failure of a picture past the export's total, naming the total.
 *
 * @param ledger - The export's ledger.
 * @returns The HANDOUT_IMAGE failure, as {@link embedOne} returns it.
 *
 * @example
 * overTotal(createImageLedger(12)) // { code: 'HANDOUT_IMAGE', reason: 'would take the pictures of the Handout past 12 bytes in all: …' }
 */
function overTotal(ledger: ImageLedger): EmbedFailure {
  return {
    code: 'HANDOUT_IMAGE',
    reason: `would take the pictures of the Handout past ${sizeText(ledger.totalLimitBytes)} in all: use fewer or smaller pictures`,
  }
}

/**
 * A byte count as a message says it: whole megabytes, else bytes.
 *
 * @param bytes - A limit in bytes.
 * @returns `100 MB` for a whole number of megabytes, else `12 bytes`.
 *
 * @example
 * sizeText(20 * 1024 * 1024) // '20 MB'
 * sizeText(12)               // '12 bytes'
 */
function sizeText(bytes: number): string {
  const megabytes = bytes / 1024 / 1024
  return Number.isInteger(megabytes) ? `${megabytes} MB` : `${bytes} bytes`
}

/** The failure of a picture over {@link IMAGE_LIMIT_BYTES}, worded as the host words a larger file. */
function tooLarge(): EmbedFailure {
  return {
    code: 'HANDOUT_IMAGE',
    reason: `is larger than ${sizeText(IMAGE_LIMIT_BYTES)}, the most a Handout embeds`,
  }
}

/**
 * Whether some bytes may go into a Handout as an image: what image they are, or why not. A picture
 * an SVG carries as data is checked the same way, one level deeper.
 *
 * @param bytes - A file's contents, or the data written into a page.
 * @param depth - How deep inside other pictures these bytes sit (0 for the picture a page names).
 * @returns
 * - `{ ok: true, mime }` for png, jpeg, gif, webp, avif and svg that carry no secret shape
 * - `{ ok: false, failure }` for other bytes and a malformed SVG (HANDOUT_IMAGE), and for a picture
 *   whose text holds a secret shape or cannot be read to check (HANDOUT_SECRET, HANDOUT_IMAGE)
 *
 * @example
 * await inspectImage(new TextEncoder().encode('{"error":"expired"}')) // { ok: false, failure: { code: 'HANDOUT_IMAGE', reason: 'is not an image: …' } }
 */
async function inspectImage(
  bytes: Uint8Array,
  depth = 0,
): Promise<{ ok: true; mime: ImageMime } | { ok: false; failure: EmbedFailure }> {
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
  // An SVG is text: a key in its text, or a signed link in one of its URLs, travels with the drawing.
  // It is read as written and as an XML reader decodes it (`&#65;KIA…`, `&amp;signature=`)
  if (mime === 'image/svg+xml') {
    const text = decodeTextByBom(bytes)
    const parsed = new DOMParser().parseFromString(text, 'image/svg+xml')
    if (parsed.getElementsByTagName('parsererror').length > 0) {
      return {
        ok: false,
        failure: {
          code: 'HANDOUT_IMAGE',
          reason: 'is not a well-formed SVG: a browser would not show it either',
        },
      }
    }
    const [finding] = findSecrets(`${text}\n${collectReadableText(parsed)}`)
    if (finding) return secretIn(finding.pattern, 'remove the value from the file')
    // A picture the drawing links (`<image href="shot.png">`) does not load where the drawing is
    // shown as an image: the Handout would show it without that picture
    const linked = linkedPicture(parsed)
    if (linked !== null) {
      return {
        ok: false,
        failure: {
          code: 'HANDOUT_IMAGE',
          reason: `draws a picture it links to (${excerpt(maskSecrets(linked))}), which it cannot show inside the Handout: embed that picture in the SVG`,
        },
      }
    }
    // A picture the drawing carries (a screenshot as data) is checked like one of its own
    for (const nested of nestedPictures(parsed)) {
      if (depth >= NESTED_PICTURE_DEPTH) {
        return { ok: false, failure: { code: 'HANDOUT_IMAGE', reason: 'nests pictures too deeply to check' } }
      }
      const data = dataUriBytes(nested)
      if (!data.ok)
        return {
          ok: false,
          failure: { code: 'HANDOUT_IMAGE', reason: `carries a picture that ${data.reason}` },
        }
      const inspected = await inspectImage(data.bytes, depth + 1)
      if (!inspected.ok) {
        return {
          ok: false,
          failure: { ...inspected.failure, reason: `carries a picture that ${inspected.failure.reason}` },
        }
      }
    }
    return { ok: true, mime }
  }
  // A raster picture's metadata (PNG text, EXIF, XMP, comments) is stored as ASCII or UTF-16 text,
  // XMP with XML's escapes (`&amp;signature=`): read as stored and decoded
  const stored = metadataSecretShape(bytes)
  if (stored) return secretIn(stored, METADATA_ADVICE, ' in its metadata')
  // A GIF keeps a comment in sub-blocks, each after a length byte that can be a letter a key would run
  // into: each extension is read on its own too, its sub-blocks joined
  if (mime === 'image/gif') {
    for (const text of gifExtensionTexts(bytes)) {
      const extensionSecret = metadataSecretShape(text)
      if (extensionSecret) return secretIn(extensionSecret, METADATA_ADVICE, ' in its metadata')
    }
  }
  if (mime === 'image/png') {
    // A PNG keeps a text chunk's text right before the chunk's CRC, whose bytes can be letters that a
    // key would run into: each chunk but the image data is read on its own too
    for (const chunk of pngChunks(bytes)) {
      const chunkSecret = chunk.type === 'IDAT' ? null : metadataSecretShape(chunk.data)
      if (chunkSecret) return secretIn(chunkSecret, METADATA_ADVICE, ' in its metadata')
    }
    // ...or compressed: each such text is inflated (all of them within one limit) and read the same way
    let inflatedBytes = 0
    for (const compressed of pngCompressedTexts(bytes)) {
      const inflated = await inflateLimited(compressed, IMAGE_LIMIT_BYTES - inflatedBytes)
      if (!inflated.ok) {
        return {
          ok: false,
          failure: {
            code: 'HANDOUT_IMAGE',
            reason: `carries compressed text that cannot be checked for secrets (${inflated.reason}); save the picture again without its metadata`,
          },
        }
      }
      inflatedBytes += inflated.bytes.length
      const compressedSecret = metadataSecretShape(inflated.bytes)
      if (compressedSecret) return secretIn(compressedSecret, METADATA_ADVICE, ' in its metadata')
    }
  }
  return { ok: true, mime }
}

/**
 * The first secret shape a raster picture's bytes hold as text: read one byte per character and
 * without zero bytes ({@link byteTexts}), each as stored and with XML's escapes decoded (XMP).
 *
 * @param raster - A picture's bytes, or text a PNG kept compressed, inflated.
 * @returns The shape's name, or null when the bytes hold none.
 *
 * @example
 * metadataSecretShape(jpegWithXmpLink) // 'signed-url-parameter'
 */
function metadataSecretShape(raster: Uint8Array): string | null {
  for (const text of byteTexts(raster)) {
    const [finding] = findSecrets(`${text}\n${decodeXmlEntities(text)}`)
    if (finding) return finding.pattern
  }
  return null
}

/**
 * Whether an SVG's link points at a file: neither data nor a reference within the drawing (`#id`).
 *
 * @param target - An href, a src or a url(…) target as written.
 * @returns Whether a picture shown as an image would have to load it.
 *
 * @example
 * isFileLink('shot.png')  // true
 * isFileLink('#gradient') // false
 */
function isFileLink(target: string): boolean {
  return target !== '' && !target.startsWith('#') && !/^data:/i.test(target)
}

/**
 * The first picture an SVG loads instead of carrying: an `<image>` or `<feImage>` whose `href` or
 * `xlink:href` is neither data nor a reference within the drawing (`#id`), an HTML `<img>` of a label
 * (foreignObject) whose `src` is not data, or a style's `url(…)` of a file.
 *
 * @param parsed - The SVG's document.
 * @returns The link as written, or null when the drawing loads no picture.
 *
 * @example
 * linkedPicture(parse('<svg …><image href="shot.png"/></svg>'))              // 'shot.png'
 * linkedPicture(parse('<svg …><rect style="fill: url(texture.png)"/></svg>')) // 'texture.png'
 */
function linkedPicture(parsed: Document): string | null {
  for (const element of Array.from(parsed.querySelectorAll('*'))) {
    const name = element.localName
    // An <image> or a filter's <feImage> names its picture in href; a label's HTML <img> in src
    const linked =
      name === 'image' || name === 'feImage'
        ? (element.getAttribute('href') ?? element.getAttribute('xlink:href') ?? '').trim()
        : name === 'img'
          ? (element.getAttribute('src') ?? '').trim()
          : ''
    if (isFileLink(linked)) return linked
    // A style (an attribute or a <style>) that loads a file by url(…)
    const styles = [
      ...Array.from(element.attributes, (attribute) => attribute.value),
      name === 'style' ? (element.textContent ?? '') : '',
    ]
    for (const style of styles) {
      for (const match of style.matchAll(/url\(\s*["']?([^"')\s]+)/gi)) {
        if (isFileLink(match[1] ?? '')) return match[1] ?? ''
      }
    }
  }
  return null
}

/**
 * The pictures an SVG carries as data: each `data:image/…` an element names in `href` or
 * `xlink:href` (an `<image>`, a filter's `<feImage>`), and each one a style's `url(…)` loads.
 *
 * @param parsed - The SVG's document.
 * @returns The data URIs, as written.
 *
 * @example
 * nestedPictures(parse('<svg …><image href="data:image/png;base64,iVBOR…"/></svg>')) // ['data:image/png;base64,iVBOR…']
 */
function nestedPictures(parsed: Document): string[] {
  const pictures: string[] = []
  for (const element of Array.from(parsed.querySelectorAll('*'))) {
    for (const attribute of Array.from(element.attributes)) {
      const value = attribute.value.trim()
      if ((attribute.name === 'href' || attribute.name === 'xlink:href') && /^data:image\//i.test(value))
        pictures.push(value)
      for (const match of attribute.value.matchAll(/url\(\s*["']?(data:image\/[^"')\s]+)/gi))
        pictures.push(match[1] ?? '')
    }
    if (element.localName === 'style') {
      for (const match of (element.textContent ?? '').matchAll(/url\(\s*["']?(data:image\/[^"')\s]+)/gi))
        pictures.push(match[1] ?? '')
    }
  }
  return pictures.filter((picture) => picture !== '')
}

/**
 * The HANDOUT_SECRET failure of a picture, naming the shape and never the value.
 *
 * @param pattern - The shape's name ({@link findSecrets}).
 * @param advice - What to do about it.
 * @param where - Where in the picture, after the shape (` in its metadata`), or nothing.
 * @returns The failure, as {@link inspectImage} returns it.
 *
 * @example
 * secretIn('aws-access-key-id', 'save the picture again without it', ' in its metadata')
 * // { ok: false, failure: { code: 'HANDOUT_SECRET', reason: 'carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it' } }
 */
function secretIn(pattern: string, advice: string, where = ''): { ok: false; failure: EmbedFailure } {
  return {
    ok: false,
    failure: { code: 'HANDOUT_SECRET', reason: `carries a secret shape (${pattern})${where}; ${advice}` },
  }
}

/** Why data written into a page is no picture: it does not decode. */
const UNDECODABLE = 'is not an image: its data cannot be decoded'

/**
 * The bytes a `data:image/…` source holds: base64 decoded, or the URL-encoded text as UTF-8. One
 * larger than {@link IMAGE_LIMIT_BYTES} is refused before it is decoded.
 *
 * @param source - The source as written in the page.
 * @returns The bytes, or why there are none to embed.
 *
 * @example
 * dataUriBytes('data:image/svg+xml,%3Csvg%3E') // { ok: true, bytes: <the bytes of '<svg>'> }
 * dataUriBytes('data:image/png;base64,@@')     // { ok: false, reason: 'is not an image: its data cannot be decoded' }
 */
function dataUriBytes(source: string): { ok: true; bytes: Uint8Array } | { ok: false; reason: string } {
  const comma = source.indexOf(',')
  if (comma < 0) return { ok: false, reason: UNDECODABLE }
  const header = source.slice(0, comma)
  const payload = source.slice(comma + 1)
  const isBase64 = /;base64$/i.test(header)
  const base64 = isBase64 ? payload.replace(/\s/g, '') : ''
  // Sizes known before anything is decoded: base64 holds three bytes in four characters (padding
  // not counted), and URL-encoded text at least one byte in three characters (`%41`)
  if (isBase64 ? base64DecodedLength(base64) > IMAGE_LIMIT_BYTES : payload.length / 3 > IMAGE_LIMIT_BYTES)
    return { ok: false, reason: tooLarge().reason }
  try {
    // Percent escapes are bytes, as a browser reads them (%89 is no UTF-8 text)
    const bytes = isBase64 ? decodeBase64(base64) : percentDecode(payload)
    return bytes.length > IMAGE_LIMIT_BYTES ? { ok: false, reason: tooLarge().reason } : { ok: true, bytes }
  } catch {
    return { ok: false, reason: UNDECODABLE }
  }
}
