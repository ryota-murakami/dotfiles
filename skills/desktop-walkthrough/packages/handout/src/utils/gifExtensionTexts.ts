/** A GIF's header ("GIF89a") and logical screen descriptor: 6 and 7 bytes, before its first block. */
const FIRST_BLOCK_OFFSET = 13

/** Where the logical screen descriptor keeps its packed fields (the global color table's flag and size). */
const SCREEN_PACKED_OFFSET = 10

/** An image descriptor: its separator, position, size and packed fields (the local color table's). */
const IMAGE_DESCRIPTOR_BYTES = 10

/** The packed fields' flag for a color table, and the bits of its size (2^(N+1) colors of 3 bytes). */
const COLOR_TABLE_FLAG = 0x80
const COLOR_TABLE_SIZE_BITS = 0x07
const COLOR_BYTES = 3

/** The bytes that start an extension and an image (the trailer, or anything else, ends the walk). */
const EXTENSION_INTRODUCER = 0x21
const IMAGE_SEPARATOR = 0x2c

/**
 * The data of each extension of a GIF (a comment, an application's data such as XMP, plain text),
 * with its sub-blocks joined: the length byte before each sub-block left out.
 *
 * Why it exists: a GIF keeps a comment in sub-blocks, each after a length byte that can be a letter;
 * read with the rest of the file, that letter runs into a key at the start of the comment, which then
 * no longer reads as one. Called by the image check of {@link embedImages}, which reads each one for
 * secret shapes. A file cut off ends the walk: what was read is all there is to check.
 *
 * @param bytes - A GIF's contents (its signature already recognized).
 * @returns Each extension's data, in file order; empty when there is none.
 *
 * @example
 * gifExtensionTexts(gifWithComment('hello')) // [Uint8Array [104, 101, 108, 108, 111]]
 */
export function gifExtensionTexts(bytes: Uint8Array): Uint8Array[] {
  const texts: Uint8Array[] = []
  let offset = FIRST_BLOCK_OFFSET + colorTableBytes(bytes[SCREEN_PACKED_OFFSET] ?? 0)
  while (offset < bytes.length) {
    const block = bytes[offset]
    if (block === EXTENSION_INTRODUCER) {
      // The introducer and the label, then the sub-blocks
      const end = subBlocksEnd(bytes, offset + 2)
      texts.push(joinedSubBlocks(bytes, offset + 2, end))
      offset = end
    } else if (block === IMAGE_SEPARATOR) {
      // The descriptor, its local color table, the LZW code size, then the image data's sub-blocks
      const packed = bytes[offset + IMAGE_DESCRIPTOR_BYTES - 1] ?? 0
      offset = subBlocksEnd(bytes, offset + IMAGE_DESCRIPTOR_BYTES + colorTableBytes(packed) + 1)
    } else {
      // The trailer, or bytes that are no block: the walk ends
      break
    }
  }
  return texts
}

/**
 * How many bytes a color table takes, from the packed fields that announce it (none without its flag).
 *
 * @example
 * colorTableBytes(0x80) // 6 (2 colors)
 * colorTableBytes(0x00) // 0
 */
function colorTableBytes(packed: number): number {
  return packed & COLOR_TABLE_FLAG ? COLOR_BYTES * 2 ** ((packed & COLOR_TABLE_SIZE_BITS) + 1) : 0
}

/**
 * Where the sub-blocks starting at OFFSET end: after their terminator (a zero length byte), or at the
 * end of a file cut off before it.
 *
 * @example
 * subBlocksEnd(new Uint8Array([2, 65, 66, 0]), 0) // 4
 */
function subBlocksEnd(bytes: Uint8Array, offset: number): number {
  let position = offset
  while (position < bytes.length) {
    const size = bytes[position] ?? 0
    position += 1 + size
    if (size === 0) break
  }
  return Math.min(position, bytes.length)
}

/**
 * The data of the sub-blocks from OFFSET to END (as {@link subBlocksEnd} found it), joined: their
 * length bytes left out.
 *
 * @example
 * joinedSubBlocks(new Uint8Array([2, 65, 66, 1, 67, 0]), 0, 6) // Uint8Array [65, 66, 67]
 */
function joinedSubBlocks(bytes: Uint8Array, offset: number, end: number): Uint8Array {
  const joined = new Uint8Array(end - offset)
  let length = 0
  let position = offset
  while (position < end) {
    const size = bytes[position] ?? 0
    const data = bytes.subarray(position + 1, Math.min(position + 1 + size, end))
    joined.set(data, length)
    length += data.length
    position += 1 + size
    if (size === 0) break
  }
  return joined.slice(0, length)
}
