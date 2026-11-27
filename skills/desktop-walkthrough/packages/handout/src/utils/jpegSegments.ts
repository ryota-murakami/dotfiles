/** Every JPEG marker starts with this byte; the file starts with the marker SOI (FF D8). */
const MARKER_PREFIX = 0xff
const SOI_BYTES = 2

/** Markers with no length or payload: TEM, and the restarts RST0 to RST7 inside image data. */
const TEM = 0x01
const FIRST_RESTART = 0xd0
const LAST_RESTART = 0xd7

/** The end of the image, and the start of a scan (image data runs from its segment to the next marker). */
const EOI = 0xd9
const SOS = 0xda

/** A segment's marker and its length (big endian, counting itself but not the marker): 2 bytes each. */
const MARKER_BYTES = 2
const LENGTH_BYTES = 2

/**
 * The payload of each marker segment of a JPEG, each on its own: what a segment holds after its marker
 * and its 2 length bytes (a comment, EXIF, XMP, an ICC profile, tables). The image data after each
 * scan is stepped over, up to the next marker.
 *
 * Why it exists: a segment's text starts right after its length, whose low byte can be a letter or a
 * digit that a key read with the rest of the file runs into; read on its own, the text starts where
 * it starts. Called by the image check of {@link embedImages}, which reads each one for secret
 * shapes. A segment cut off by the end of the file gives what is left of it and ends the walk.
 *
 * @param bytes - A JPEG's contents (its signature already recognized).
 * @returns Each segment's payload, in file order; empty when there is none.
 *
 * @example
 * jpegSegments(new Uint8Array([0xff, 0xd8, 0xff, 0xfe, 0x00, 0x03, 0x41, 0xff, 0xd9])) // [Uint8Array [0x41]]
 */
export function jpegSegments(bytes: Uint8Array): Uint8Array[] {
  const segments: Uint8Array[] = []
  let offset = SOI_BYTES
  while (offset + MARKER_BYTES <= bytes.length && bytes[offset] === MARKER_PREFIX) {
    const marker = bytes[offset + 1] ?? 0
    // A fill byte before a marker, or a marker without a payload
    if (marker === MARKER_PREFIX) {
      offset += 1
      continue
    }
    if (marker === TEM || (marker >= FIRST_RESTART && marker <= LAST_RESTART)) {
      offset += MARKER_BYTES
      continue
    }
    if (marker === EOI) break
    const start = offset + MARKER_BYTES + LENGTH_BYTES
    const end = offset + MARKER_BYTES + (((bytes[offset + 2] ?? 0) << 8) | (bytes[offset + 3] ?? 0))
    segments.push(bytes.subarray(Math.min(start, bytes.length), Math.min(Math.max(end, start), bytes.length)))
    if (end > bytes.length) break
    offset = Math.max(end, start)
    // A scan's image data runs to the next marker: FF followed by neither a stuffed 00 nor a restart
    if (marker === SOS) offset = nextMarker(bytes, offset)
  }
  return segments
}

/**
 * Where the next marker after image data starts: the first FF followed by neither 00 (a stuffed byte)
 * nor a restart marker.
 *
 * @example
 * nextMarker(new Uint8Array([0x11, 0xff, 0x00, 0xff, 0xfe]), 0) // 3
 */
function nextMarker(bytes: Uint8Array, from: number): number {
  for (let offset = from; offset + 1 < bytes.length; offset++) {
    const next = bytes[offset + 1] ?? 0
    if (bytes[offset] === MARKER_PREFIX && next !== 0x00 && !(next >= FIRST_RESTART && next <= LAST_RESTART))
      return offset
  }
  return bytes.length
}
