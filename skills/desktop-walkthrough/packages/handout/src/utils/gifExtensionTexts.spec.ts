import { expect, test } from 'vitest'

import { gifExtensionTexts } from './gifExtensionTexts'

/** "GIF89a" and a 1×1 logical screen; with a global color table of two colors when asked. */
function gifHead(withColorTable = false): number[] {
  const screen = [
    0x47,
    0x49,
    0x46,
    0x38,
    0x39,
    0x61,
    0x01,
    0x00,
    0x01,
    0x00,
    withColorTable ? 0x80 : 0x00,
    0x00,
    0x00,
  ]
  return withColorTable ? [...screen, 0, 0, 0, 0xff, 0xff, 0xff] : screen
}

test('each extension gives its data with the sub-blocks joined, their length bytes left out', () => {
  // Arrange
  const gif = new Uint8Array([...gifHead(), 0x21, 0xfe, 0x02, 0x41, 0x42, 0x01, 0x43, 0x00, 0x3b])

  // Act
  const texts = gifExtensionTexts(gif).map((text) => Array.from(text))

  // Assert
  expect(texts).toEqual([[0x41, 0x42, 0x43]])
})

test('the color tables and the image data are stepped over: an extension after an image is read too', () => {
  // Arrange
  const image = [
    0x2c, 0, 0, 0, 0, 0x01, 0x00, 0x01, 0x00, 0x80, 0, 0, 0, 0xff, 0xff, 0xff, 0x02, 0x02, 0x44, 0x01, 0x00,
  ]
  const gif = new Uint8Array([...gifHead(true), ...image, 0x21, 0xfe, 0x01, 0x45, 0x00, 0x3b])

  // Act
  const texts = gifExtensionTexts(gif).map((text) => Array.from(text))

  // Assert
  expect(texts).toEqual([[0x45]])
})

test('a file cut off inside an extension gives what was read of it', () => {
  // Arrange
  const gif = new Uint8Array([...gifHead(), 0x21, 0xfe, 0x05, 0x41, 0x42])

  // Act
  const texts = gifExtensionTexts(gif).map((text) => Array.from(text))

  // Assert
  expect(texts).toEqual([[0x41, 0x42]])
})
