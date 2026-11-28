/** "RIFF", the file's size and its form type ("WEBP"): 4 bytes each, before the first chunk. */
const FIRST_CHUNK_OFFSET = 12

/** A chunk's type and its size (little endian) before its data: 4 bytes each. */
const CHUNK_FIELD_BYTES = 4

/**
 * The data of each chunk of a RIFF file (a WebP), each on its own: what a chunk holds after its type
 * and size, without the pad byte that follows an odd size.
 *
 * Why it exists: a chunk's data is followed by the next chunk's type, four letters that a key at the
 * end of the data runs into when read with the rest of the file; read on its own, the data ends where
 * it ends. Called by the image check of {@link embedImages}, which reads each one for secret shapes. A
 * chunk cut off by the end of the file gives what is left of it and ends the walk.
 *
 * @param bytes - A WebP's contents (its signature already recognized).
 * @returns Each chunk's data, in file order; empty when there is none.
 *
 * @example
 * riffChunks(webp) // [Uint8Array (VP8X data), Uint8Array (XMP data), …]
 */
export function riffChunks(bytes: Uint8Array): Uint8Array[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const chunks: Uint8Array[] = []
  let offset = FIRST_CHUNK_OFFSET
  while (offset + 2 * CHUNK_FIELD_BYTES <= bytes.length) {
    const start = offset + 2 * CHUNK_FIELD_BYTES
    const end = start + view.getUint32(offset + CHUNK_FIELD_BYTES, true)
    chunks.push(bytes.subarray(start, Math.min(end, bytes.length)))
    if (end > bytes.length) break
    // An odd size is followed by a pad byte
    offset = end + ((end - start) % 2)
  }
  return chunks
}
