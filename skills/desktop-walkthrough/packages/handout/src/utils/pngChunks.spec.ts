import { expect, test } from 'vitest'

import { pngChunks } from './pngChunks'

/** A PNG made of the signature and the given chunks (type, data), each with a CRC of zeros. */
function pngOf(chunks: Array<[string, number[]]>): Uint8Array {
  const parts: number[] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  for (const [type, data] of chunks) {
    parts.push(
      0,
      0,
      0,
      data.length,
      ...Array.from(type, (character) => character.charCodeAt(0)),
      ...data,
      0,
      0,
      0,
      0,
    )
  }
  return new Uint8Array(parts)
}

test('every chunk before IEND comes with its type and its data alone, without its CRC', () => {
  // Arrange
  const png = pngOf([
    ['tEXt', [0x41, 0x00, 0x42]],
    ['IDAT', [0x01]],
    ['IEND', []],
    ['tEXt', [0x43]],
  ])

  // Act
  const chunks = pngChunks(png).map(({ type, data }) => [type, Array.from(data)])

  // Assert
  expect(chunks).toEqual([
    ['tEXt', [0x41, 0x00, 0x42]],
    ['IDAT', [0x01]],
  ])
})

test('a chunk cut off by the end of the file comes with what is left of its data, and ends the walk', () => {
  // Arrange
  const png = pngOf([['tEXt', [0x41, 0x42, 0x43]]]).slice(0, -6)

  // Act
  const chunks = pngChunks(png).map(({ type, data }) => [type, Array.from(data)])

  // Assert
  expect(chunks).toEqual([['tEXt', [0x41]]])
})
