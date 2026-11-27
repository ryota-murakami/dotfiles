import { expect, test } from 'vitest'

import { riffChunks } from './riffChunks'

/** "RIFF", a size, "WEBP" and the given chunks (type, data), each padded to an even length. */
function webpOf(chunks: Array<[string, number[]]>): Uint8Array {
  const body = chunks.flatMap(([type, data]) => [
    ...Array.from(type, (character) => character.charCodeAt(0)),
    data.length,
    0,
    0,
    0,
    ...data,
    ...(data.length % 2 === 1 ? [0] : []),
  ])
  return new Uint8Array([0x52, 0x49, 0x46, 0x46, body.length + 4, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, ...body])
}

test('each chunk gives its data alone, without its type, size or pad byte', () => {
  // Arrange
  const webp = webpOf([
    ['XMP ', [0x41]],
    ['EXIF', [0x42, 0x43]],
  ])

  // Act
  const chunks = riffChunks(webp).map((chunk) => Array.from(chunk))

  // Assert
  expect(chunks).toEqual([[0x41], [0x42, 0x43]])
})

test('a chunk cut off by the end of the file gives what is left of it', () => {
  // Arrange
  const webp = webpOf([['XMP ', [0x41, 0x42, 0x43, 0x44]]]).slice(0, -2)

  // Act
  const chunks = riffChunks(webp).map((chunk) => Array.from(chunk))

  // Assert
  expect(chunks).toEqual([[0x41, 0x42]])
})
