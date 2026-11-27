import { UTF16_BIG_ENDIAN_BOM, UTF16_LITTLE_ENDIAN_BOM } from '../constants'

/**
 * Decode text bytes as their byte order mark says: UTF-16 (little or big endian) after its mark,
 * UTF-8 otherwise. The mark is not part of the text.
 *
 * Why it exists: an SVG is text, and one saved as UTF-16 starts with its mark; read as UTF-8 it
 * would be neither recognized as a picture nor read by the secret check. Called by
 * {@link sniffImage} for the start of a file and by the image check of {@link embedImages} for an
 * SVG's text, so that both read the same text.
 *
 * @param bytes - The text's bytes.
 * @returns The text.
 *
 * @example
 * decodeTextByBom(new Uint8Array([0xff, 0xfe, 0x3c, 0x00])) // '<'
 * decodeTextByBom(new TextEncoder().encode('<svg'))         // '<svg'
 */
export function decodeTextByBom(bytes: Uint8Array): string {
  const startsWith = (mark: readonly number[]) => mark.every((byte, index) => bytes[index] === byte)
  let encoding = 'utf-8'
  if (startsWith(UTF16_LITTLE_ENDIAN_BOM)) encoding = 'utf-16le'
  else if (startsWith(UTF16_BIG_ENDIAN_BOM)) encoding = 'utf-16be'
  return new TextDecoder(encoding).decode(bytes)
}
