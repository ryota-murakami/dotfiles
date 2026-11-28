import { expect, test } from 'vitest'

import { jpegSegments } from './jpegSegments'

test('each marker segment gives its payload alone, without its marker and length bytes', () => {
  // Arrange
  const jpeg = new Uint8Array([
    0xff, 0xd8, 0xff, 0xfe, 0x00, 0x04, 0x41, 0x42, 0xff, 0xe1, 0x00, 0x03, 0x43, 0xff, 0xd9,
  ])

  // Act
  const segments = jpegSegments(jpeg).map((segment) => Array.from(segment))

  // Assert
  expect(segments).toEqual([[0x41, 0x42], [0x43]])
})

test('the image data after a scan is stepped over, stuffed bytes and restarts included: a comment after it is read', () => {
  // Arrange
  const scan = [0xff, 0xda, 0x00, 0x02, 0x11, 0xff, 0x00, 0x22, 0xff, 0xd0, 0x33]
  const jpeg = new Uint8Array([0xff, 0xd8, ...scan, 0xff, 0xfe, 0x00, 0x03, 0x44, 0xff, 0xd9])

  // Act
  const segments = jpegSegments(jpeg).map((segment) => Array.from(segment))

  // Assert
  expect(segments).toEqual([[], [0x44]])
})

test('a segment cut off by the end of the file gives what is left of it', () => {
  // Arrange
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xfe, 0x00, 0x10, 0x41, 0x42])

  // Act
  const segments = jpegSegments(jpeg).map((segment) => Array.from(segment))

  // Assert
  expect(segments).toEqual([[0x41, 0x42]])
})
