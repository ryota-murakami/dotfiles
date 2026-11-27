import { maskSecrets } from '../../../../hooks/secrets'
import type { Diagnostic, HandoutPage, Warning } from '../contract'
import { excerpt } from '../utils/excerpt'

/** Elements a Handout cannot carry: their media would be a dead player in the colleague's copy. */
const MEDIA_ELEMENTS: ReadonlySet<string> = new Set(['video', 'audio'])

/** Attributes whose value a browser loads to show the element (an `<img>`'s `src` is embedded, not loaded). */
const LOADED_ATTRIBUTES: ReadonlySet<string> = new Set(['src', 'poster', 'background', 'data'])

/** Attributes whose value a reader follows: a link. */
const LINK_ATTRIBUTES: ReadonlySet<string> = new Set([
  'href',
  'xlink:href',
  'action',
  'formaction',
  'cite',
  'longdesc',
])

/** Each `url(…)` in a style or an attribute, its target in group 1 (quotes and spaces trimmed by the caller). */
const CSS_URL = /url\(\s*([^)]*?)\s*\)/gi

/**
 * Find what a sanitized page points at that the Handout does not carry: media (a video, a sound),
 * a picture loaded by a style or an attribute rather than embedded, and links to files on this Mac.
 *
 * Why it exists: a Handout is one file that opens anywhere, and when dw says "written" it works as
 * checked (DX D6). Pictures are embedded and checked ({@link embedImages}); anything else a page
 * loads would show as a dead player or a missing picture, carrying the author's paths (their user
 * name) besides, and a style's `url(data:…)` would put bytes in the file that no secret check read.
 * Those stop the export (HANDOUT_IMAGE). A link to a local file stops nothing: the page still reads,
 * and the agent is warned that the colleague cannot follow it. Called by {@link buildHandout} for
 * every page after sanitizing.
 *
 * @param page - The page the content belongs to (its number names it in messages).
 * @param html - The page's sanitized content, pictures embedded.
 * @returns HANDOUT_IMAGE diagnostics, and one warning per link to a local file; both empty for a page that points at nothing outside itself.
 *
 * @example
 * checkReferences(page, '<p><a href="file:///Users/u/notes.md">メモ</a></p>')
 * // { diagnostics: [], warnings: [{ message: "links to file:///Users/u/notes.md, a file on this Mac: the colleague's copy cannot open it", page: 4 }] }
 * checkReferences(page, '<video src="demo.mov"></video>')
 * // { diagnostics: [{ code: 'HANDOUT_IMAGE', message: 'page 4: a video cannot go into a Handout, …', page: 4 }], warnings: [] }
 */
export function checkReferences(
  page: HandoutPage,
  html: string,
): { diagnostics: Diagnostic[]; warnings: Warning[] } {
  const holder = document.createElement('template')
  holder.innerHTML = html
  const diagnostics: Diagnostic[] = []
  const warnings: Warning[] = []
  const stop = (message: string) =>
    diagnostics.push({ code: 'HANDOUT_IMAGE', message: `page ${page.n}: ${message}`, page: page.n })
  for (const element of Array.from(holder.content.querySelectorAll('*'))) {
    const name = element.localName
    // A video or a sound is reported once: its own sources and tracks say nothing more
    if (MEDIA_ELEMENTS.has(name)) {
      stop(
        `a ${name} cannot go into a Handout, which carries pictures only: show a picture of it, or link to where it is shared`,
      )
      continue
    }
    if (element.closest('video, audio')) continue
    // A diagram's own style sheet: what it loads goes unchecked like a style attribute's
    if (name === 'style') for (const target of loadedUrls(element.textContent ?? '')) stop(styleLoads(target))
    for (const attribute of Array.from(element.attributes)) {
      for (const target of loadedUrls(attribute.value)) stop(styleLoads(target))
      const embeddedPicture = name === 'img' || (name === 'image' && element.closest('svg') !== null)
      if (LOADED_ATTRIBUTES.has(attribute.name) && !embeddedPicture && attribute.value.trim() !== '') {
        stop(
          `the ${name} element loads ${quoted(attribute.value)}, which a Handout does not carry: show the picture with an image instead`,
        )
      }
      // An SVG <image>'s href is its picture, embedded like an <img>'s src
      if (LINK_ATTRIBUTES.has(attribute.name) && !embeddedPicture && isLocalReference(attribute.value)) {
        warnings.push({
          message: `links to ${quoted(attribute.value)}, a file on this Mac: the colleague's copy cannot open it`,
          page: page.n,
        })
      }
    }
  }
  return { diagnostics, warnings }
}

/**
 * The targets of every `url(…)` in a text that load something: everything but a reference within
 * the document (`url(#arrow)`, how a diagram points at its own markers and gradients).
 *
 * @param text - A style attribute, a presentation attribute or a style sheet.
 * @returns The targets, quotes trimmed.
 *
 * @example
 * loadedUrls('fill: url(#gradient); background: url("data:image/png;base64,iVBOR")') // ['data:image/png;base64,iVBOR']
 */
function loadedUrls(text: string): string[] {
  return Array.from(text.matchAll(CSS_URL), (match) => (match[1] ?? '').replace(/^["']|["']$/g, '')).filter(
    (target) => !target.startsWith('#'),
  )
}

/** The message of a style that loads TARGET. */
function styleLoads(target: string): string {
  return `a style loads ${quoted(target)}, which a Handout neither checks nor carries: show the picture with an image instead`
}

/** A value as a message quotes it: secret shapes masked, cut short. */
function quoted(value: string): string {
  return excerpt(maskSecrets(value))
}

/**
 * Whether a link points at a file on this Mac: a `file:` link, or a path with no scheme (absolute,
 * relative, or `//host/…`, which a file opened from disk resolves to a file too). A link within the
 * page (`#設定`) and one with a scheme (`https:`, `mailto:`) are not.
 *
 * @param value - The attribute's value.
 * @returns Whether the colleague's copy cannot follow it.
 *
 * @example
 * isLocalReference('02-設定.md')          // true
 * isLocalReference('https://example.com') // false
 * isLocalReference('#設定')               // false
 */
function isLocalReference(value: string): boolean {
  const target = value.trim()
  if (target === '' || target.startsWith('#')) return false
  return /^file:/i.test(target) || !/^[a-z][a-z0-9+.-]*:/i.test(target)
}
