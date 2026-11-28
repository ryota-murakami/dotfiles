import { maskSecrets } from '../../../../hooks/secrets'
import { XLINK_NAMESPACE } from '../constants'
import type { Diagnostic, HandoutPage, Warning } from '../contract'
import { cssLoads } from '../utils/cssLoads'
import { excerpt } from '../utils/excerpt'

/** Elements a Handout cannot carry: their media would be a dead player in the colleague's copy. */
const MEDIA_ELEMENTS: ReadonlySet<string> = new Set(['video', 'audio'])

/** Attributes whose value a browser loads to show the element (an `<img>`'s `src` is embedded, not loaded). */
const LOADED_ATTRIBUTES: ReadonlySet<string> = new Set(['src', 'poster', 'background', 'data'])

/**
 * Diagram elements that draw the file their `href` names: a filter's picture, and a `<use>` of a
 * shape in another file. Every other `href` in a diagram names a part of the page (a gradient, a
 * pattern, a path) or is a link; an `<image>` is embedded by {@link embedImages}.
 */
const DRAWN_BY_REFERENCE: ReadonlySet<string> = new Set(['feImage', 'use'])

/** Attributes whose value a reader follows: a link. */
const LINK_ATTRIBUTES: ReadonlySet<string> = new Set([
  'href',
  'xlink:href',
  'action',
  'formaction',
  'cite',
  'longdesc',
])

/**
 * Attributes whose value is CSS, where `url(…)` loads something: `style`, and the SVG presentation
 * attributes that take a paint server, a filter, a clip, a mask, a marker or a cursor. Any other
 * attribute (an `alt` that explains `url(x.png)`) is text, never read as CSS.
 */
const CSS_ATTRIBUTES: ReadonlySet<string> = new Set([
  'style',
  'fill',
  'stroke',
  'filter',
  'clip-path',
  'mask',
  'marker-start',
  'marker-mid',
  'marker-end',
  'cursor',
])

/**
 * Find what a sanitized page loads that the Handout does not carry: media (a video, a sound), and a
 * picture, a style sheet or a font loaded by CSS or an attribute rather than embedded.
 *
 * Why it exists: a Handout is one file that opens anywhere, and when dw says "written" it works as
 * checked (DX D6). Pictures are embedded and checked ({@link embedImages}); anything else a page
 * loads would show as a dead player or a missing picture, carrying the author's paths (their user
 * name) besides, and a style's `url(data:…)` would put bytes in the file that no secret check read.
 * CSS is read where CSS is (style attributes, SVG presentation attributes, a diagram's `<style>`):
 * `url(…)`, the strings of `image-set(…)` and `@import`. Called by {@link buildHandout} for every
 * page after sanitizing: what the colleague receives.
 *
 * @param page - The page the content belongs to (its number names it in messages).
 * @param html - The page's sanitized content, pictures embedded.
 * @returns One HANDOUT_IMAGE per media element and per thing loaded; empty for a page that loads nothing.
 *
 * @example
 * unembeddableResources(page, '<video src="demo.mov"></video>')
 * // [{ code: 'HANDOUT_IMAGE', message: 'page 4: a video cannot go into a Handout, …', page: 4 }]
 */
export function unembeddableResources(page: HandoutPage, html: string): Diagnostic[] {
  const holder = document.createElement('template')
  holder.innerHTML = html
  const diagnostics: Diagnostic[] = []
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
    // A diagram's own style sheet loads like a style attribute
    if (name === 'style') for (const target of cssLoads(element.textContent ?? '')) stop(styleLoads(target))
    const embeddedPicture = name === 'img' || (name === 'image' && element.closest('svg') !== null)
    for (const attribute of Array.from(element.attributes)) {
      if (CSS_ATTRIBUTES.has(attribute.name))
        for (const target of cssLoads(attribute.value)) stop(styleLoads(target))
      if (LOADED_ATTRIBUTES.has(attribute.name) && !embeddedPicture && attribute.value.trim() !== '') {
        stop(
          `the ${name} element loads ${quoted(attribute.value)}, which a Handout does not carry: show the picture with an image instead`,
        )
      }
    }
  }
  return diagnostics
}

/**
 * Find the diagram elements of a page that draw a file they name by `href` (an `<feImage>`, a `<use>`
 * of another file): the Handout carries no such file, so the drawing would be incomplete.
 *
 * Why it exists: the sanitizer removes a `<use>` and a `file:` address, so after it such a drawing
 * would lose its part without a word; read before it, the agent learns. Only the `href` a browser
 * follows counts: SVG 2's, else XLink's, so an unused legacy fallback beside a `#id` stops nothing.
 * Called by {@link buildHandout} for every page after its pictures are embedded and before it is
 * sanitized.
 *
 * @param page - The page the content belongs to (its number names it in messages).
 * @param html - The page's content, pictures embedded, not yet sanitized.
 * @returns One HANDOUT_IMAGE per element that draws a file; empty when every reference is within the page.
 *
 * @example
 * drawnFiles(page, '<svg><use href="parts.svg#box"></use></svg>')
 * // [{ code: 'HANDOUT_IMAGE', message: 'page 4: the use element loads parts.svg#box, …', page: 4 }]
 * drawnFiles(page, '<svg><use href="#box"></use></svg>') // []
 */
export function drawnFiles(page: HandoutPage, html: string): Diagnostic[] {
  const holder = document.createElement('template')
  holder.innerHTML = html
  const diagnostics: Diagnostic[] = []
  for (const element of Array.from(holder.content.querySelectorAll('*'))) {
    if (!DRAWN_BY_REFERENCE.has(element.localName) || element.closest('svg') === null) continue
    const reference = (
      element.getAttribute('href') ??
      element.getAttributeNS(XLINK_NAMESPACE, 'href') ??
      ''
    ).trim()
    // Nothing named, or a part of the page (`#id`): nothing loads
    if (reference === '' || reference.startsWith('#')) continue
    diagnostics.push({
      code: 'HANDOUT_IMAGE',
      message: `page ${page.n}: the ${element.localName} element loads ${quoted(reference)}, which a Handout does not carry: show the picture with an image instead`,
      page: page.n,
    })
  }
  return diagnostics
}

/**
 * Find the links of a page that point at files on this Mac, which the colleague's copy cannot open.
 *
 * Why it exists: a link to a local file still reads as text, so it stops nothing, but the agent
 * should know (a link the sanitizer removes, such as `file:`, would otherwise vanish without a word).
 * Called by {@link buildHandout} for every page after its pictures are embedded and before it is
 * sanitized, while every link still has its address.
 *
 * @param page - The page the content belongs to (its number goes with each warning).
 * @param html - The page's content, pictures embedded, not yet sanitized.
 * @returns One warning per link to a local file; empty when there is none.
 *
 * @example
 * localLinks(page, '<p><a href="file:///Users/u/notes.md">メモ</a></p>')
 * // [{ message: "links to file:///Users/u/notes.md, a file on this Mac: the colleague's copy cannot open it", page: 4 }]
 */
export function localLinks(page: HandoutPage, html: string): Warning[] {
  const holder = document.createElement('template')
  holder.innerHTML = html
  const warnings: Warning[] = []
  for (const element of Array.from(holder.content.querySelectorAll('*'))) {
    // An SVG <image>'s href is its picture, embedded like an <img>'s src
    if (element.localName === 'image' && element.closest('svg') !== null) continue
    for (const attribute of Array.from(element.attributes)) {
      if (LINK_ATTRIBUTES.has(attribute.name) && isLocalReference(attribute.value)) {
        warnings.push({
          message: `links to ${quoted(attribute.value)}, a file on this Mac: the colleague's copy cannot open it`,
          page: page.n,
        })
      }
    }
  }
  return warnings
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
