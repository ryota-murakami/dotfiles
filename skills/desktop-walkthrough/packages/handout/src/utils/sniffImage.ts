import { IMAGE_SIGNATURES, SVG_SNIFF_BYTES } from '../constants'

/** The image types a Handout embeds, as `data:` URIs name them. */
export type ImageMime = (typeof IMAGE_SIGNATURES)[number]['mime'] | 'image/svg+xml'

/**
 * Tell what image a file's bytes hold from the bytes themselves, never from the file's name.
 *
 * Why it exists: an image is embedded byte for byte into a file that leaves the machine. A path that
 * names `shot.png` can hold anything: a saved error page, or (through a symlink) a credential file.
 * Called by {@link embedImages} for every image, read from a file or written into the page as data.
 *
 * @param bytes - The file's contents.
 * @returns
 * - the image's MIME type when the bytes start like png, jpeg, gif, webp, avif or svg
 * - null for anything else
 *
 * @example
 * sniffImage(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) // 'image/png'
 * sniffImage(new TextEncoder().encode('{"error":"the link expired"}'))       // null
 */
export function sniffImage(bytes: Uint8Array): ImageMime | null {
  const signature = IMAGE_SIGNATURES.find(({ parts }) =>
    parts.every(({ offset, bytes: expected }) =>
      expected.every((byte, index) => bytes[offset + index] === byte),
    ),
  )
  if (signature) return signature.mime
  // SVG is text: its <svg element comes first, after an optional byte order mark, XML declaration,
  // comments and doctype
  const head = new TextDecoder().decode(bytes.slice(0, SVG_SNIFF_BYTES))
  const body = head
    .replace(/^﻿/, '')
    .replace(/^\s*(?:<\?xml[\s\S]*?\?>\s*)?(?:(?:<!--[\s\S]*?-->|<!DOCTYPE[^>]*>)\s*)*/i, '')
  return /^<svg[\s>/]/i.test(body) ? 'image/svg+xml' : null
}
