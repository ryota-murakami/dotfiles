/**
 * How many bytes some base64 text decodes to, padding not counted, without decoding it.
 *
 * Why it exists: a picture written into a page as `data:…;base64,` is refused when larger than the
 * limit before it is decoded (decoding is the allocation to avoid), and one of exactly the limit
 * must not be taken for a larger one. Called by the image check of {@link embedImages}.
 *
 * @param base64 - Base64 text without whitespace, padded or not.
 * @returns The decoded size in bytes.
 *
 * @example
 * base64DecodedLength('aGk=') // 2
 * base64DecodedLength('aGk')  // 2
 */
export function base64DecodedLength(base64: string): number {
  const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0
  return Math.floor((base64.length * 3) / 4) - padding
}
