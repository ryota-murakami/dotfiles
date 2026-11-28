import { expect, test } from 'vitest'

import { sniffImage } from './sniffImage'

/** The bytes of a text, as a file holding it. */
const textBytes = (text: string) => new TextEncoder().encode(text)

test('each image type a Handout embeds is told by its first bytes', () => {
  // Arrange
  const files = {
    png: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]),
    jpeg: new Uint8Array([0xff, 0xd8, 0xff, 0xe0]),
    gif: textBytes('GIF89a'),
    webp: textBytes('RIFF\u0000\u0000\u0000\u0000WEBPVP8 '),
    avif: textBytes('\u0000\u0000\u0000 ftypavif'),
  }

  // Act
  const types = Object.values(files).map((bytes) => sniffImage(bytes))

  // Assert
  expect(types).toEqual(['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/avif'])
})

test('an SVG is told after its XML declaration, comments and doctype', () => {
  // Arrange
  const svg = textBytes(
    '﻿<?xml version="1.0"?>\n<!-- drawn by hand -->\n<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n<svg xmlns="http://www.w3.org/2000/svg"></svg>',
  )

  // Act
  const type = sniffImage(svg)

  // Assert
  expect(type).toBe('image/svg+xml')
})

test('a text saved under an image name is not an image', () => {
  // Arrange
  const files = [
    textBytes('{"error":"the link expired"}'),
    textBytes('<!doctype html><html><body>404</body></html>'),
    new Uint8Array([]),
  ]

  // Act
  const types = files.map((bytes) => sniffImage(bytes))

  // Assert
  expect(types).toEqual([null, null, null])
})

test('an SVG is told after a doctype holding declarations of its own', () => {
  // Arrange
  const bytes = new TextEncoder().encode(
    '<?xml version="1.0"?>\n<!DOCTYPE svg [<!ELEMENT svg ANY>]>\n<svg xmlns="http://www.w3.org/2000/svg"></svg>',
  )

  // Act
  const mime = sniffImage(bytes)

  // Assert
  expect(mime).toBe('image/svg+xml')
})

test('an SVG saved as UTF-16 is told by its byte order mark, little or big endian', () => {
  // Arrange
  const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
  const littleEndian = new Uint8Array([
    0xff,
    0xfe,
    ...Array.from(svg).flatMap((character) => [character.charCodeAt(0), 0]),
  ])
  const bigEndian = new Uint8Array([
    0xfe,
    0xff,
    ...Array.from(svg).flatMap((character) => [0, character.charCodeAt(0)]),
  ])

  // Act
  const mimes = [sniffImage(littleEndian), sniffImage(bigEndian)]

  // Assert
  expect(mimes).toEqual(['image/svg+xml', 'image/svg+xml'])
})
