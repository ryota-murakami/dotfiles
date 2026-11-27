import { pngChunks } from './pngChunks'

/**
 * The compressed text a PNG carries, still compressed (zlib): every `zTXt` chunk, each `iTXt` chunk
 * whose compression flag is set, and the color profile of `iCCP` (its descriptions are text too).
 *
 * Why it exists: a picture is embedded byte for byte, and text a PNG keeps compressed reads as noise
 * until it is inflated, a key in it included. Called by the image check of {@link embedImages},
 * which inflates each one and looks for secret shapes in it. A chunk cut off by the end of the file
 * ends the walk: the bytes read so far are all there is to check.
 *
 * @param bytes - A PNG's contents (its signature already recognized).
 * @returns The compressed text of each such chunk, in file order; empty when there is none.
 *
 * @example
 * pngCompressedTexts(png) // [Uint8Array [120, 156, …]] for one zTXt chunk
 */
export function pngCompressedTexts(bytes: Uint8Array): Uint8Array[] {
  const texts: Uint8Array[] = []
  for (const { type, data } of pngChunks(bytes)) {
    const keywordEnd = data.indexOf(0)
    // zTXt: keyword, NUL, compression method, the compressed text; iCCP the same, with a color profile
    if ((type === 'zTXt' || type === 'iCCP') && keywordEnd >= 0) texts.push(data.subarray(keywordEnd + 2))
    // iTXt: keyword, NUL, compression flag, method, language tag, NUL, translated keyword, NUL, the text
    if (type === 'iTXt' && keywordEnd >= 0 && data[keywordEnd + 1] === 1) {
      const languageEnd = data.indexOf(0, keywordEnd + 3)
      const translatedEnd = languageEnd < 0 ? -1 : data.indexOf(0, languageEnd + 1)
      if (translatedEnd >= 0) texts.push(data.subarray(translatedEnd + 1))
    }
  }
  return texts
}
