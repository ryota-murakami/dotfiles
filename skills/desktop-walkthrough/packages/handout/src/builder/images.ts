import { maskSecrets } from '../../../../hooks/secrets'
import type { Diagnostic, HandoutPage } from '../contract'
import { excerpt } from '../utils/excerpt'
import { resolvePath } from '../utils/resolvePath'
import type { HostPort } from './host'
import { readFile } from './host'

/** The image types a Handout embeds, by file extension. */
const IMAGE_TYPES: Readonly<Record<string, string>> = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  gif: 'image/gif',
  webp: 'image/webp',
  avif: 'image/avif',
  svg: 'image/svg+xml',
}

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
 */
export function classifySource(source: string, pagesDir: string): ImageSource {
  if (/^data:image\//i.test(source)) return { kind: 'embedded' }
  const withoutQuery = source.replace(/[?#].*$/, '')
  if (/^file:\/\//i.test(source)) return { kind: 'file', path: decodeURIComponent(new URL(source).pathname) }
  if (/^[a-z][a-z0-9+.-]*:/i.test(source) || source.startsWith('//'))
    return { kind: 'refused', reason: 'is not a local file' }
  const path = decodeURIComponent(withoutQuery)
  return { kind: 'file', path: path.startsWith('/') ? path : resolvePath(pagesDir, path) }
}

/**
 * Embed every local image of a rendered page as a `data:` URI, so the Handout works as one file (DX D15).
 *
 * Why it exists: the colleague receives the HTML file alone; a path on this Mac means nothing on
 * theirs. An image that cannot be embedded stops the export (HANDOUT_IMAGE) with the line where the
 * page names it, rather than shipping a broken picture. Called by {@link buildHandout} per page.
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
  const images = Array.from(holder.content.querySelectorAll('img'))
  // Nothing to embed: the content goes on exactly as rendered
  if (images.length === 0) return { html, diagnostics: [] }
  const sourceLines = page.markdown.split('\n')
  const diagnostics: Diagnostic[] = []
  for (const image of images) {
    const source = image.getAttribute('src') ?? ''
    const classified = classifySource(source, `${recordDir}/pages`)
    if (classified.kind === 'embedded') continue
    const reason = await embedOne(image, classified, host)
    if (reason === null) continue
    const index = sourceLines.findIndex((text) => source !== '' && text.includes(source))
    const where = index < 0 ? maskSecrets(page.source) : `${maskSecrets(page.source)}:${index + 1}`
    diagnostics.push({
      code: 'HANDOUT_IMAGE',
      message: `${where}: the image ${excerpt(maskSecrets(source || '(no src)'))} ${reason}`,
      page: page.n,
      ...(index < 0 ? {} : { line: index + 1 }),
    })
  }
  return { html: holder.innerHTML, diagnostics }
}

/**
 * Put one image's bytes into its `src`.
 *
 * @returns null when embedded; otherwise why it could not be, worded to follow "the image X".
 */
async function embedOne(
  image: HTMLImageElement,
  source: Exclude<ImageSource, { kind: 'embedded' }>,
  host: HostPort,
): Promise<string | null> {
  if (source.kind === 'refused') return source.reason
  const extension = /\.([A-Za-z0-9]+)$/.exec(source.path)?.[1]?.toLowerCase() ?? ''
  const type = IMAGE_TYPES[extension]
  if (type === undefined) return 'is not a type the Handout embeds (png, jpg, gif, webp, avif, svg)'
  const read = await readFile(host, source.path)
  if (!read.ok) return `could not be read: ${excerpt(maskSecrets(read.message))}`
  image.setAttribute('src', `data:${type};base64,${read.base64}`)
  return null
}
