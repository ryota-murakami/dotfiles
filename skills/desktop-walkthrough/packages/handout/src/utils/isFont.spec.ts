import { expect, test } from 'vitest'

import { isFont } from './isFont'

test('data that starts like a WOFF2, WOFF, OpenType or TrueType font is told as a font', () => {
  // Arrange
  const woff2 = new Uint8Array([0x77, 0x4f, 0x46, 0x32, 0x00, 0x01])
  const woff = new Uint8Array([0x77, 0x4f, 0x46, 0x46, 0x00, 0x01])
  const openType = new Uint8Array([0x4f, 0x54, 0x54, 0x4f, 0x00, 0x0a])
  const trueType = new Uint8Array([0x00, 0x01, 0x00, 0x00, 0x00, 0x0a])

  // Act
  const told = [woff2, woff, openType, trueType].map(isFont)

  // Assert
  expect(told).toEqual([true, true, true, true])
})

test('a picture or a style sheet is no font, so an SVG cannot carry one unchecked as a font', () => {
  // Arrange
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
  const sheet = new TextEncoder().encode('rect { fill: url(shot.png) }')

  // Act
  const told = [png, sheet].map(isFont)

  // Assert
  expect(told).toEqual([false, false])
})

test('data shorter than a font signature is no font', () => {
  // Arrange
  const cut = new Uint8Array([0x77, 0x4f])

  // Act
  const told = [cut, new Uint8Array()].map(isFont)

  // Assert
  expect(told).toEqual([false, false])
})
