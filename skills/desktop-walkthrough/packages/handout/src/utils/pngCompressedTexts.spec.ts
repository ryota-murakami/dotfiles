import { deflateSync } from 'node:zlib'

import { expect, test } from 'vitest'

import { pngCompressedTexts } from './pngCompressedTexts'

/** A PNG made of the signature and the given chunks (type, data); CRCs are left zero, as nothing here reads them. */
function pngWith(chunks: Array<[string, Uint8Array]>, end = true): Uint8Array {
  const parts: number[] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  const all: Array<[string, Uint8Array]> = end ? [...chunks, ['IEND', new Uint8Array()]] : chunks
  for (const [type, data] of all) {
    parts.push(
      (data.length >>> 24) & 0xff,
      (data.length >>> 16) & 0xff,
      (data.length >>> 8) & 0xff,
      data.length & 0xff,
    )
    parts.push(...Array.from(type, (character) => character.charCodeAt(0)), ...data, 0, 0, 0, 0)
  }
  return new Uint8Array(parts)
}

const encode = (text: string) => new TextEncoder().encode(text)

test('a compressed iTXt chunk gives its compressed text, after its language tag and translated keyword', () => {
  // Arrange
  const text = deflateSync(encode('秘密の説明'))
  const iTXt = new Uint8Array([
    ...encode('Comment'),
    0,
    1,
    0,
    ...encode('ja'),
    0,
    ...encode('説明'),
    0,
    ...text,
  ])

  // Act
  const texts = pngCompressedTexts(pngWith([['iTXt', iTXt]]))

  // Assert
  expect(texts.map((compressed) => Array.from(compressed))).toEqual([Array.from(text)])
})

test('an uncompressed iTXt chunk gives nothing: its text is read with the other bytes', () => {
  // Arrange
  const iTXt = new Uint8Array([...encode('Comment'), 0, 0, 0, ...encode('ja'), 0, 0, ...encode('平文')])

  // Act
  const texts = pngCompressedTexts(pngWith([['iTXt', iTXt]]))

  // Assert
  expect(texts).toEqual([])
})

test('a chunk cut off by the end of the file ends the walk without reading past it', () => {
  // Arrange
  const whole = pngWith(
    [['zTXt', new Uint8Array([...encode('A'), 0, 0, ...deflateSync(encode('x'))])]],
    false,
  )
  const cut = whole.subarray(0, whole.length - 6)

  // Act
  const texts = pngCompressedTexts(cut)

  // Assert
  expect(texts).toEqual([])
})

test('a zTXt chunk after IEND is not read: the picture ends there', () => {
  // Arrange
  const png = new Uint8Array([
    ...pngWith([]),
    ...pngWith(
      [['zTXt', new Uint8Array([...encode('A'), 0, 0, ...deflateSync(encode('x'))])]],
      false,
    ).subarray(8),
  ])

  // Act
  const texts = pngCompressedTexts(png)

  // Assert
  expect(texts).toEqual([])
})

test('a compressed color profile (iCCP) gives its compressed bytes, like zTXt', () => {
  // Arrange
  const profile = deflateSync(encode('desc profile'))
  const iCCP = new Uint8Array([...encode('ICC'), 0, 0, ...profile])

  // Act
  const texts = pngCompressedTexts(pngWith([['iCCP', iCCP]]))

  // Assert
  expect(texts.map((compressed) => Array.from(compressed))).toEqual([Array.from(profile)])
})
