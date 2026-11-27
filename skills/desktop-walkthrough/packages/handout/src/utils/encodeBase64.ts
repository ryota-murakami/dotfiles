import { BASE64_CHUNK_BYTES } from '../constants'

/**
 * Encode bytes as base64, in chunks small enough for `String.fromCharCode`'s argument limit.
 *
 * Why it exists: a picture written into a page as data is embedded as its checked bytes alone,
 * rebuilt as `data:<type>;base64,…`, so no other text of the source (a parameter of the data URI)
 * travels unchecked. Called by {@link embedImages}.
 *
 * @param bytes - The bytes, up to the 20 MB a picture may have.
 * @returns Their base64 text.
 *
 * @example
 * encodeBase64(new Uint8Array([104, 105])) // 'aGk='
 */
export function encodeBase64(bytes: Uint8Array): string {
  let binary = ''
  for (let offset = 0; offset < bytes.length; offset += BASE64_CHUNK_BYTES) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + BASE64_CHUNK_BYTES))
  }
  return btoa(binary)
}
