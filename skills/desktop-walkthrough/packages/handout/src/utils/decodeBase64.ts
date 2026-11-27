/**
 * Turn the host's base64 reply to a `read` request into bytes.
 *
 * @param base64 - The `base64` field of a `file` reply.
 * @returns The file's bytes.
 *
 * @example
 * decodeBase64('aGk=') // Uint8Array [104, 105]
 */
export function decodeBase64(base64: string): Uint8Array {
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))
}
