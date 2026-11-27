/** Where a PNG's chunks start: after its 8-byte signature. */
const FIRST_CHUNK_OFFSET = 8

/** A chunk's length and type before its data, its CRC after: 4 bytes each. */
const CHUNK_FIELD_BYTES = 4

/**
 * The chunks of a PNG up to `IEND`, each as its type and its data alone (its length and CRC left out).
 *
 * Why it exists: a PNG keeps a text chunk's text right before the chunk's CRC, whose bytes can be
 * letters that a key read as text would run into; read on its own, the text ends where it ends. Called
 * by the image check of {@link embedImages}, which reads each chunk for secret shapes, and by
 * {@link pngCompressedTexts}. A chunk cut off by the end of the file comes with what is left of it
 * and ends the walk: a key at its start is read on its own too, and compressed text in it fails to
 * inflate, which refuses the picture rather than passing it unread.
 *
 * @param bytes - A PNG's contents (its signature already recognized).
 * @returns Each chunk's type and data, in file order; empty for a file with no whole chunk.
 *
 * @example
 * pngChunks(png) // [{ type: 'IHDR', data: Uint8Array(13) }, { type: 'tEXt', data: … }, …]
 */
export function pngChunks(bytes: Uint8Array): Array<{ type: string; data: Uint8Array }> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const chunks: Array<{ type: string; data: Uint8Array }> = []
  let offset = FIRST_CHUNK_OFFSET
  while (offset + 2 * CHUNK_FIELD_BYTES <= bytes.length) {
    const start = offset + 2 * CHUNK_FIELD_BYTES
    const end = start + view.getUint32(offset)
    const type = String.fromCharCode(...bytes.subarray(offset + CHUNK_FIELD_BYTES, start))
    if (type === 'IEND') break
    // A chunk cut off by the end of the file comes with what is left of it, and ends the walk
    chunks.push({ type, data: bytes.subarray(start, Math.min(end, bytes.length)) })
    if (end > bytes.length) break
    offset = end + CHUNK_FIELD_BYTES
  }
  return chunks
}
