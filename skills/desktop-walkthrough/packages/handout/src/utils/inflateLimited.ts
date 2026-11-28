import { INFLATE_INPUT_CHUNK_BYTES } from '../constants'

/** Why compressed bytes could not be inflated: no inflater in this WebKit, broken data, or more than allowed. */
export type InflateFailure = 'unavailable' | 'broken' | 'too-large'

/**
 * Inflate zlib-compressed bytes (a PNG's compressed text), giving up once the result passes a limit.
 *
 * Why it exists: text a picture keeps compressed must be read before the picture leaves the machine,
 * and a small chunk can inflate to gigabytes. Called by the image check of {@link embedImages} for
 * each chunk {@link pngCompressedTexts} found; every failure stops the picture, since its text could
 * not be checked.
 *
 * @param compressed - zlib data (RFC 1950), as a PNG stores it.
 * @param limitBytes - The most bytes the inflated text may have.
 * @returns
 * - `{ ok: true, bytes }`: the inflated bytes
 * - `{ ok: false, reason }`: why not ({@link InflateFailure})
 *
 * @example
 * await inflateLimited(deflated('hello'), 1_000) // { ok: true, bytes: Uint8Array [104, 101, 108, 108, 111] }
 * await inflateLimited(new Uint8Array([1, 2, 3]), 1_000) // { ok: false, reason: 'broken' }
 */
export async function inflateLimited(
  compressed: Uint8Array,
  limitBytes: number,
): Promise<{ ok: true; bytes: Uint8Array } | { ok: false; reason: InflateFailure }> {
  if (typeof DecompressionStream === 'undefined') return { ok: false, reason: 'unavailable' }
  // The compressed bytes go in a little at a time, as the inflater asks for more: a small input that
  // inflates to gigabytes is stopped once its output passes the limit, never inflated whole first
  let fed = 0
  const input = new ReadableStream<BufferSource>(
    {
      pull(controller) {
        if (fed >= compressed.length) {
          controller.close()
          return
        }
        controller.enqueue(compressed.slice(fed, fed + INFLATE_INPUT_CHUNK_BYTES))
        fed += INFLATE_INPUT_CHUNK_BYTES
      },
    },
    { highWaterMark: 0 },
  )
  const reader = input.pipeThrough(new DecompressionStream('deflate')).getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.byteLength
      // Past the limit: stop inflating at once rather than hold the rest
      if (total > limitBytes) {
        await reader.cancel()
        return { ok: false, reason: 'too-large' }
      }
      chunks.push(value)
    }
  } catch {
    return { ok: false, reason: 'broken' }
  }
  const bytes = new Uint8Array(total)
  let offset = 0
  for (const chunk of chunks) {
    bytes.set(chunk, offset)
    offset += chunk.byteLength
  }
  return { ok: true, bytes }
}
