import { FONT_SIGNATURES } from '../constants'

/**
 * Tell whether some bytes are a font from the bytes themselves: WOFF2, WOFF, OpenType or TrueType.
 *
 * Why it exists: an SVG may carry a font as data for its text (a drawing tool embeds the one it drew
 * with), and a font is no picture to check. The type the data's URI declares decides nothing: a
 * browser shows a picture whatever it is called. Called by {@link embedImages} for each piece of
 * data an SVG carries.
 *
 * @param bytes - The data's bytes.
 * @returns Whether they start like a font ({@link FONT_SIGNATURES}).
 *
 * @example
 * isFont(new Uint8Array([0x77, 0x4f, 0x46, 0x32, 0x00, 0x01])) // true: `wOF2`
 * isFont(new Uint8Array([0x89, 0x50, 0x4e, 0x47]))             // false: a PNG
 */
export function isFont(bytes: Uint8Array): boolean {
  return FONT_SIGNATURES.some((signature) => signature.every((byte, index) => bytes[index] === byte))
}
