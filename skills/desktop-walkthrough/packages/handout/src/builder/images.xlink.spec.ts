// @vitest-environment jsdom
// jsdom reads an XML prefix as the name of its namespace, as WebKit does (happy-dom keeps `x:href` as
// a name of its own): these specs need that to see XLink under a prefix the drawing chose
import { expect, test } from 'vitest'

import type { HostReply, HostRequest } from '../contract'
import type { HostPort } from './host'
import { createImageLedger, embedImages } from './images'

/** A host whose files are the given map (path → base64). */
function hostWithFiles(files: Record<string, string>): HostPort {
  return async (request: HostRequest): Promise<HostReply> => {
    if (request.type !== 'read') throw new Error(`unexpected ${request.type}`)
    const base64 = files[request.path]
    return base64 === undefined ? { type: 'unreadable', message: 'no such file' } : { type: 'file', base64 }
  }
}

const page = (markdown: string) => ({
  n: 3,
  title: '画面',
  section: '確認',
  markdown,
  built: 'pages/003.html',
})

/** Base64 of a text, as the host sends file contents. */
function toBase64(text: string): string {
  return btoa(String.fromCharCode(...new TextEncoder().encode(text)))
}

/** Base64 of some bytes, as the host sends file contents. */
function bytesToBase64(bytes: Uint8Array): string {
  return btoa(Array.from(bytes, (byte) => String.fromCharCode(byte)).join(''))
}

// An AWS access key id of the documented example shape, assembled at run time so secret scanners do
// not flag this public file
const ACCESS_KEY_ID = ['AKIA', 'IOSFODNN7EXAMPLE'].join('')

/** A PNG made of the signature, one tEXt chunk holding TEXT, and IEND; CRCs are left zero. */
function pngWithText(text: string): Uint8Array {
  const parts: number[] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  for (const [type, data] of [
    ['tEXt', new TextEncoder().encode(text)],
    ['IEND', new Uint8Array()],
  ] as Array<[string, Uint8Array]>) {
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

test('an SVG that links a picture through XLink under a prefix of its own stops the export like a plain href', async () => {
  // Arrange
  const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/1999/xlink"><image x:href="shot.png" width="10" height="10"/></svg>'
  const host = hostWithFiles({ '/r/pages/prefixed.svg': toBase64(svg) })
  const html = '<p><img src="prefixed.svg"></p>'

  // Act
  const result = await embedImages(page('![図](prefixed.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image prefixed.svg draws a picture it links to (shot.png), which it cannot show inside the Handout: embed that picture in the SVG',
  ])
})

test('a screenshot an SVG carries through XLink under a prefix of its own is checked like one on its own', async () => {
  // Arrange
  const png = pngWithText(`Comment\0${ACCESS_KEY_ID}`)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/1999/xlink"><image x:href="data:image/png;base64,${bytesToBase64(png)}" width="10" height="10"/></svg>`
  const host = hostWithFiles({ '/r/pages/diagram.svg': toBase64(svg) })
  const html = '<p><img src="diagram.svg"></p>'

  // Act
  const result = await embedImages(page('![図](diagram.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => [diagnostic.code, diagnostic.message])).toEqual([
    [
      'HANDOUT_SECRET',
      'page 3:1: the image diagram.svg carries a picture that carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
    ],
  ])
})

test('an SVG that links a picture through xlink:href, its usual prefix, stops the export too', async () => {
  // Arrange
  const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="shot.png" width="10" height="10"/></svg>'
  const host = hostWithFiles({ '/r/pages/usual.svg': toBase64(svg) })
  const html = '<p><img src="usual.svg"></p>'

  // Act
  const result = await embedImages(page('![図](usual.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image usual.svg draws a picture it links to (shot.png), which it cannot show inside the Handout: embed that picture in the SVG',
  ])
})
