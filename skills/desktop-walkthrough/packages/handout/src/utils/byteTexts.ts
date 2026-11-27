/**
 * Read a picture's bytes as text the ways its metadata holds text: one byte per character (PNG text
 * chunks, EXIF strings, XMP, a JPEG or GIF comment), and the same without zero bytes, which turns
 * UTF-16 text (Windows writes EXIF comments so) into one byte per character too.
 *
 * Why it exists: a picture is embedded byte for byte, so a key in its metadata reaches the colleague
 * with it. The secret shapes are ASCII; both readings show them wherever the file stores them as
 * ASCII or UTF-16. The first reading keeps what the second would join to a neighbouring letter.
 * Called by the image check of {@link embedImages} for every png, jpeg, gif, webp and avif.
 *
 * @param bytes - A picture's contents.
 * @returns The two readings, each one character per byte.
 *
 * @example
 * byteTexts(new Uint8Array([0x41, 0x00, 0x4b, 0x00])) // ['A\u0000K\u0000', 'AK']
 */
export function byteTexts(bytes: Uint8Array): [string, string] {
  const decoder = new TextDecoder('latin1')
  return [decoder.decode(bytes), decoder.decode(bytes.filter((byte) => byte !== 0))]
}
