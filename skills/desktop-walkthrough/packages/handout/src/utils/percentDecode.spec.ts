import { expect, test } from 'vitest'

import { percentDecode } from './percentDecode'

test('a percent escape is the byte it names, even one that is no UTF-8 text (%89)', () => {
  // Arrange
  const text = '%89PNG%0d%0A'

  // Act
  const bytes = percentDecode(text)

  // Assert
  expect(Array.from(bytes)).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
})

test('a percent sign without two hexadecimal digits stays, and other characters are their UTF-8 bytes', () => {
  // Arrange
  const text = '%2g%4日'

  // Act
  const bytes = percentDecode(text)

  // Assert
  expect(Array.from(bytes)).toEqual([0x25, 0x32, 0x67, 0x25, 0x34, 0xe6, 0x97, 0xa5])
})
