import { expect, test } from 'vitest'

import { decodeTextByBom } from './decodeTextByBom'

test('text after a UTF-16 byte order mark is read as UTF-16, little or big endian, without the mark', () => {
  // Arrange
  const littleEndian = new Uint8Array([0xff, 0xfe, 0x3c, 0x00, 0x73, 0x00])
  const bigEndian = new Uint8Array([0xfe, 0xff, 0x00, 0x3c, 0x00, 0x73])

  // Act
  const texts = [decodeTextByBom(littleEndian), decodeTextByBom(bigEndian)]

  // Assert
  expect(texts).toEqual(['<s', '<s'])
})

test('text without a UTF-16 mark is read as UTF-8, its own mark dropped', () => {
  // Arrange
  const bytes = new Uint8Array([0xef, 0xbb, 0xbf, 0x3c, 0xe6, 0x97, 0xa5])

  // Act
  const text = decodeTextByBom(bytes)

  // Assert
  expect(text).toBe('<日')
})
