/** The byte of `%`, which starts a percent escape. */
const PERCENT_SIGN = '%'.charCodeAt(0)

/**
 * Percent-decode text into bytes, as a browser reads the data of a `data:` URL: `%XX` is the byte
 * XX, a `%` without two hexadecimal digits stays as it is, and every other character is its UTF-8
 * bytes.
 *
 * Why it exists: a picture written into a page as `data:image/png,%89PNG…` holds bytes that are no
 * UTF-8 text, which `decodeURIComponent` refuses. Called by the image check of {@link embedImages}
 * for data that is not base64.
 *
 * @param text - The data part of the URL.
 * @returns The bytes it stands for.
 *
 * @example
 * percentDecode('%89PNG') // Uint8Array [0x89, 0x50, 0x4e, 0x47]
 * percentDecode('100%')   // Uint8Array [0x31, 0x30, 0x30, 0x25]
 */
export function percentDecode(text: string): Uint8Array {
  const encoded = new TextEncoder().encode(text)
  const decoded = new Uint8Array(encoded.length)
  let length = 0
  for (let index = 0; index < encoded.length; index++) {
    const escape = String.fromCharCode(encoded[index + 1] ?? 0, encoded[index + 2] ?? 0)
    // `%` and two hexadecimal digits are one byte; anything else is itself
    if (encoded[index] === PERCENT_SIGN && /^[\da-f]{2}$/i.test(escape)) {
      decoded[length++] = Number.parseInt(escape, 16)
      index += 2
    } else {
      decoded[length++] = encoded[index] ?? 0
    }
  }
  return decoded.slice(0, length)
}
