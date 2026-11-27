import { deflateSync } from 'node:zlib'

import { expect, test } from 'vitest'

import type { HostReply, HostRequest } from '../contract'
import type { HostPort } from './host'
import { createImageLedger, embedImages } from './images'

/** A host whose files are the given map (path → base64); it records every path asked for. */
function hostWithFiles(files: Record<string, string>): HostPort & { asked: string[] } {
  const asked: string[] = []
  const host = async (request: HostRequest): Promise<HostReply> => {
    if (request.type !== 'read') throw new Error(`unexpected ${request.type}`)
    asked.push(request.path)
    const base64 = files[request.path]
    return base64 === undefined ? { type: 'unreadable', message: 'no such file' } : { type: 'file', base64 }
  }
  return Object.assign(host, { asked })
}

const page = (markdown: string) => ({
  n: 3,
  title: '画面',
  section: '確認',
  markdown,
  built: 'pages/003.html',
})

test('an image beside the page is embedded, so the Handout works as one file', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const html = '<p><img src="shot.png" alt="一覧の画面"></p>'

  // Act
  const result = await embedImages(page('![一覧の画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result).toEqual({
    html: '<p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" alt="一覧の画面"></p>',
    diagnostics: [],
  })
})

test('an image named by absolute path or file link is read from that path', async () => {
  // Arrange
  const host = hostWithFiles({ '/Users/u/Desktop/a b.jpg': '/9j/4AAQ', '/tmp/c.svg': 'PHN2Zy8+' })
  const html = '<p><img src="/Users/u/Desktop/a%20b.jpg"><img src="file:///tmp/c.svg"></p>'

  // Act
  const result = await embedImages(page(''), html, '/r', host, createImageLedger())

  // Assert
  expect(result.html).toBe(
    '<p><img src="data:image/jpeg;base64,/9j/4AAQ"><img src="data:image/svg+xml;base64,PHN2Zy8+"></p>',
  )
  expect(host.asked).toEqual(['/Users/u/Desktop/a b.jpg', '/tmp/c.svg'])
})

test('a missing image stops the export at the line that names it', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="/tmp/screenshot-1.png" alt="画面"></p>'

  // Act
  const result = await embedImages(
    page('# 画面\n\n![画面](/tmp/screenshot-1.png)\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_IMAGE',
      message: 'page 3:3: the image /tmp/screenshot-1.png could not be read: no such file',
      page: 3,
      line: 3,
    },
  ])
})

test('an image from the web stops the export: the Handout loads nothing from outside', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="https://cdn.test/logo.png"></p>'

  // Act
  const result = await embedImages(
    page('![](https://cdn.test/logo.png)\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_IMAGE',
      message: 'page 3:1: the image https://cdn.test/logo.png is not a local file',
      page: 3,
      line: 1,
    },
  ])
  expect(host.asked).toEqual([])
})

test('a file the Handout cannot show as an image stops the export, judged by its bytes', async () => {
  // Arrange
  const host = hostWithFiles({ '/r/pages/notes.pdf': 'JVBERi0=' })
  const html = '<p><img src="notes.pdf"></p>'

  // Act
  const result = await embedImages(page('<img src="notes.pdf">\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image notes.pdf is not an image: its bytes are not png, jpeg, gif, webp, avif or svg',
  ])
})

test('a page without images goes on exactly as rendered', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html =
    '<svg id="p3-d1"><foreignObject width="70" height="24"><div>書き出す</div></foreignObject></svg>'

  // Act
  const result = await embedImages(page(''), html, '/r', host, createImageLedger())

  // Assert
  expect(result).toEqual({ html, diagnostics: [] })
})

test('an image with a short name is located at the line that writes it as an image, not at any line with its letters', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="x"></p>'

  // Act
  const result = await embedImages(
    page('# 画面\n\nexport const x = 1\n\n<img src="x">\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.line)).toEqual([5])
})

/** Base64 of a text, as the host sends file contents. */
function toBase64(text: string): string {
  return btoa(String.fromCharCode(...new TextEncoder().encode(text)))
}

// A fake signature is assembled at run time so secret scanners do not flag this public file.
const SIGNATURE = '0f3a'.repeat(16)

test('a file named like an image whose bytes are not one stops the export instead of shipping its contents', async () => {
  // Arrange
  const host = hostWithFiles({ '/r/pages/shot.png': toBase64('{"error":"the link expired"}') })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result).toEqual({
    html,
    diagnostics: [
      {
        code: 'HANDOUT_IMAGE',
        message:
          'page 3:1: the image shot.png is not an image: its bytes are not png, jpeg, gif, webp, avif or svg',
        page: 3,
        line: 1,
      },
    ],
  })
})

test('an image saved under the wrong extension is embedded as the type its bytes are', async () => {
  // Arrange
  const host = hostWithFiles({ '/r/pages/shot.png': '/9j/4AAQ' })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result).toEqual({ html: '<p><img src="data:image/jpeg;base64,/9j/4AAQ"></p>', diagnostics: [] })
})

test('an SVG carrying a signed link in its metadata stops the export as a secret, never printing it', async () => {
  // Arrange
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><metadata>https://docs.test/a?signature=${SIGNATURE}</metadata></svg>`
  const host = hostWithFiles({ '/r/pages/flow.svg': toBase64(svg) })
  const html = '<p><img src="flow.svg"></p>'

  // Act
  const result = await embedImages(page('![流れ](flow.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message:
        'page 3:1: the image flow.svg carries a secret shape (signed-url-parameter); remove the value from the file',
      page: 3,
      line: 1,
    },
  ])
  expect(JSON.stringify(result.diagnostics)).not.toContain(SIGNATURE)
})

test('an image written into the page as data is checked like a file: an SVG with a signed link stops the export', async () => {
  // Arrange
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><desc>https://docs.test/a?signature=${SIGNATURE}</desc></svg>`
  const source = `data:image/svg+xml;base64,${toBase64(svg)}`
  const host = hostWithFiles({})
  const html = `<p><img src="${source}"></p>`

  // Act
  const result = await embedImages(page(`<img src="${source}">\n`), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => [diagnostic.code, diagnostic.line])).toEqual([
    ['HANDOUT_SECRET', 1],
  ])
})

test('an image path with a broken %-escape stops the export with a reason instead of an exception', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="shot%zz.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot%zz.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image shot%zz.png has a malformed %-escape in its path',
  ])
  expect(host.asked).toEqual([])
})

test('an image an inline SVG draws is embedded too, so the finished file shows it under its CSP', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const html = '<svg viewBox="0 0 10 10"><image href="shot.png" width="10" height="10"></image></svg>'

  // Act
  const result = await embedImages(
    page('<svg viewBox="0 0 10 10"><image href="shot.png"/></svg>\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result).toEqual({
    html: '<svg viewBox="0 0 10 10"><image href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" width="10" height="10"></image></svg>',
    diagnostics: [],
  })
})

// An AWS access key id of the documented example shape, assembled at run time like the values above
const ACCESS_KEY_ID = ['AKIA', 'IOSFODNN7EXAMPLE'].join('')

/** Base64 of some bytes, as the host sends file contents. */
function bytesToBase64(bytes: Uint8Array): string {
  return btoa(Array.from(bytes, (byte) => String.fromCharCode(byte)).join(''))
}

/** A PNG made of the signature and the given chunks (type, data); CRCs are left zero, as nothing here reads them. */
function pngWith(chunks: Array<[string, Uint8Array]>): Uint8Array {
  const parts: number[] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  for (const [type, data] of [...chunks, ['IEND', new Uint8Array()] as [string, Uint8Array]]) {
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

test('a picture without an image extension is embedded by what its bytes are', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/capture':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const html = '<p><img src="capture"></p>'

  // Act
  const result = await embedImages(page('![画面](capture)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result).toEqual({
    html: '<p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="></p>',
    diagnostics: [],
  })
})

test('an SVG that spells a key with character references stops the export, as the drawing shows it decoded', async () => {
  // Arrange
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><text>&#65;${ACCESS_KEY_ID.slice(1)}</text></svg>`
  const host = hostWithFiles({ '/r/pages/key.svg': toBase64(svg) })
  const html = '<p><img src="key.svg"></p>'

  // Act
  const result = await embedImages(page('![鍵](key.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message:
        'page 3:1: the image key.svg carries a secret shape (aws-access-key-id); remove the value from the file',
      page: 3,
      line: 1,
    },
  ])
})

test('an SVG link whose signature follows &amp;amp; stops the export, as an XML reader decodes it', async () => {
  // Arrange
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><a href="https://docs.test/a?expires=1&amp;signature=${SIGNATURE}"><text>メモ</text></a></svg>`
  const host = hostWithFiles({ '/r/pages/link.svg': toBase64(svg) })
  const html = '<p><img src="link.svg"></p>'

  // Act
  const result = await embedImages(page('![メモ](link.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => [diagnostic.code, diagnostic.message])).toEqual([
    [
      'HANDOUT_SECRET',
      'page 3:1: the image link.svg carries a secret shape (signed-url-parameter); remove the value from the file',
    ],
  ])
})

test('a key an SVG splits across the spans of one text stops the export', async () => {
  // Arrange
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><text>${ACCESS_KEY_ID.slice(0, 4)}<tspan>${ACCESS_KEY_ID.slice(4)}</tspan></text></svg>`
  const host = hostWithFiles({ '/r/pages/split.svg': toBase64(svg) })
  const html = '<p><img src="split.svg"></p>'

  // Act
  const result = await embedImages(page('![図](split.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_SECRET'])
})

test('an SVG that is not well-formed XML stops the export: its text cannot be checked, and no browser shows it', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/broken.svg': toBase64('<svg xmlns="http://www.w3.org/2000/svg"><text>未完</svg>'),
  })
  const html = '<p><img src="broken.svg"></p>'

  // Act
  const result = await embedImages(page('![図](broken.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image broken.svg is not a well-formed SVG: a browser would not show it either',
  ])
})

test('a key in a PNG’s text metadata stops the export: the bytes travel with the picture', async () => {
  // Arrange
  const png = pngWith([['tEXt', new TextEncoder().encode(`Comment\0${ACCESS_KEY_ID}`)]])
  const host = hostWithFiles({ '/r/pages/shot.png': bytesToBase64(png) })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message:
        'page 3:1: the image shot.png carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
      page: 3,
      line: 1,
    },
  ])
  expect(JSON.stringify(result.diagnostics)).not.toContain(ACCESS_KEY_ID)
})

test('a key in a PNG’s compressed text metadata stops the export once it is inflated', async () => {
  // Arrange
  const compressed = deflateSync(new TextEncoder().encode(`URL https://docs.test/a?signature=${SIGNATURE}`))
  const zTXt = new Uint8Array([...new TextEncoder().encode('Comment'), 0, 0, ...compressed])
  const host = hostWithFiles({ '/r/pages/shot.png': bytesToBase64(pngWith([['zTXt', zTXt]])) })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => [diagnostic.code, diagnostic.message])).toEqual([
    [
      'HANDOUT_SECRET',
      'page 3:1: the image shot.png carries a secret shape (signed-url-parameter) in its metadata; save the picture again without it',
    ],
  ])
})

test('a key in UTF-16 metadata of a JPEG (as Windows writes comments) stops the export', async () => {
  // Arrange
  const utf16 = Array.from(ACCESS_KEY_ID, (character) => [character.charCodeAt(0), 0]).flat()
  const jpeg = new Uint8Array([
    0xff,
    0xd8,
    0xff,
    0xe1,
    0x00,
    0x30,
    ...new TextEncoder().encode('Exif'),
    0,
    0,
    0x20,
    ...utf16,
    0,
    0,
  ])
  const host = hostWithFiles({ '/r/pages/photo.jpg': bytesToBase64(jpeg) })
  const html = '<p><img src="photo.jpg"></p>'

  // Act
  const result = await embedImages(page('![写真](photo.jpg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_SECRET'])
})

test('an image written into the page as data larger than 20 MB stops the export before it is decoded', async () => {
  // Arrange
  const source = `data:image/png;base64,${'A'.repeat(28 * 1024 * 1024)}`
  const host = hostWithFiles({})
  const html = `<p><img src="${source}"></p>`

  // Act
  const result = await embedImages(
    page('<img src="data:image/png;base64,…">\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_IMAGE'])
  expect(result.diagnostics[0]?.message).toContain('is larger than 20 MB, the most a Handout embeds')
})

test('a picture shown on two pages is read once for the whole export', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const ledger = createImageLedger()
  const html = '<p><img src="shot.png"></p>'

  // Act
  await embedImages(page('![画面](shot.png)\n'), html, '/r', host, ledger)
  const second = await embedImages({ ...page('![画面](shot.png)\n'), n: 4 }, html, '/r', host, ledger)

  // Assert
  expect(host.asked).toEqual(['/r/pages/shot.png'])
  expect(second.html).toBe(
    '<p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="></p>',
  )
})

test('pictures past the export’s total stop it, naming the one that crossed the line', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/a.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    '/r/pages/b.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  // Each picture is 67 bytes: the first fits in 100, the second crosses it
  const ledger = createImageLedger(100)
  const html = '<p><img src="a.png"><img src="b.png"></p>'

  // Act
  const result = await embedImages(page('![一](a.png)\n![二](b.png)\n'), html, '/r', host, ledger)

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:2: the image b.png would take the pictures of the Handout past 100 bytes in all: use fewer or smaller pictures',
  ])
})

test('a file link to another computer is refused without reading a local file of the same path', async () => {
  // Arrange
  const host = hostWithFiles({
    '/share/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const html = '<p><img src="file://fileserver/share/shot.png"></p>'

  // Act
  const result = await embedImages(
    page('![画面](file://fileserver/share/shot.png)\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image file://fileserver/share/shot.png names a file on another computer: copy the picture to this Mac and point at it there',
  ])
  expect(host.asked).toEqual([])
})

test('an SVG image naming its picture twice (href and xlink:href) has both checked', async () => {
  // Arrange
  const hidden = `<svg xmlns="http://www.w3.org/2000/svg"><desc>${ACCESS_KEY_ID}</desc></svg>`
  const host = hostWithFiles({
    '/r/pages/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const html = `<svg viewBox="0 0 10 10"><image href="shot.png" xlink:href="data:image/svg+xml;base64,${toBase64(hidden)}"></image></svg>`

  // Act
  const result = await embedImages(page(''), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_SECRET'])
})

test('a signed link a JPEG keeps in its XMP with an escaped & stops the export, as an XMP reader decodes it', async () => {
  // Arrange
  const xmp = `<x:xmpmeta><rdf:Description dc:source="https://docs.test/a?expires=1&amp;signature=${SIGNATURE}"/></x:xmpmeta>`
  const jpeg = new Uint8Array([
    0xff,
    0xd8,
    0xff,
    0xe1,
    0x00,
    0x10,
    ...new TextEncoder().encode(`http://ns.adobe.com/xap/1.0/\0${xmp}`),
  ])
  const host = hostWithFiles({ '/r/pages/photo.jpg': bytesToBase64(jpeg) })
  const html = '<p><img src="photo.jpg"></p>'

  // Act
  const result = await embedImages(page('![写真](photo.jpg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => [diagnostic.code, diagnostic.message])).toEqual([
    [
      'HANDOUT_SECRET',
      'page 3:1: the image photo.jpg carries a secret shape (signed-url-parameter) in its metadata; save the picture again without it',
    ],
  ])
})

test('a screenshot an SVG carries inside it is checked like one on its own: a key in its metadata stops the export', async () => {
  // Arrange
  const png = pngWith([['tEXt', new TextEncoder().encode(`Comment\0${ACCESS_KEY_ID}`)]])
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><image href="data:image/png;base64,${bytesToBase64(png)}" width="10" height="10"/></svg>`
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

test('an image written into the page as data is embedded as its checked bytes alone: no other text of the source travels', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html =
    '<p><img src="data:image/png;name=&quot;x&quot;;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="></p>'

  // Act
  const result = await embedImages(
    page('<img src="data:image/png;base64,…">\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result).toEqual({
    html: '<p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="></p>',
    diagnostics: [],
  })
})

test('once the pictures pass the total, the files after them are not read at all', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/a.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    '/r/pages/b.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    '/r/pages/c.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  // Each picture is 67 bytes: the first fits in 100, the second crosses it
  const ledger = createImageLedger(100)
  const html = '<p><img src="a.png"><img src="b.png"><img src="c.png"></p>'

  // Act
  const result = await embedImages(
    page('![一](a.png)\n![二](b.png)\n![三](c.png)\n'),
    html,
    '/r',
    host,
    ledger,
  )

  // Assert
  expect(host.asked).toEqual(['/r/pages/a.png', '/r/pages/b.png'])
  expect(result.diagnostics.map((diagnostic) => diagnostic.line)).toEqual([2, 3])
})

test('compressed metadata that cannot be inflated stops the export: its text could not be checked', async () => {
  // Arrange
  const zTXt = new Uint8Array([...new TextEncoder().encode('Comment'), 0, 0, 1, 2, 3, 4])
  const host = hostWithFiles({ '/r/pages/shot.png': bytesToBase64(pngWith([['zTXt', zTXt]])) })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image shot.png carries compressed text that cannot be checked for secrets (broken); save the picture again without its metadata',
  ])
})

test('compressed metadata whose chunks inflate past 20 MB together stops the export, however small each one is', async () => {
  // Arrange
  const chunk = new Uint8Array([
    ...new TextEncoder().encode('Comment'),
    0,
    0,
    ...deflateSync(new Uint8Array(12 * 1024 * 1024)),
  ])
  const host = hostWithFiles({
    '/r/pages/shot.png': bytesToBase64(
      pngWith([
        ['zTXt', chunk],
        ['zTXt', chunk],
      ]),
    ),
  })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image shot.png carries compressed text that cannot be checked for secrets (too-large); save the picture again without its metadata',
  ])
})

test('a key in a PNG’s compressed color profile stops the export: the profile is text a reader can recover', async () => {
  // Arrange
  const iCCP = new Uint8Array([
    ...new TextEncoder().encode('ICC'),
    0,
    0,
    ...deflateSync(new TextEncoder().encode(`desc ${ACCESS_KEY_ID}`)),
  ])
  const host = hostWithFiles({ '/r/pages/shot.png': bytesToBase64(pngWith([['iCCP', iCCP]])) })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_SECRET'])
})

test('the ledger counts the raster pictures embedded, whose pixels no check reads', async () => {
  // Arrange
  const host = hostWithFiles({
    '/r/pages/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    '/r/pages/flow.svg': 'PHN2Zy8+',
  })
  const ledger = createImageLedger()
  const html = '<p><img src="shot.png"><img src="flow.svg"><img src="shot.png"></p>'

  // Act
  await embedImages(page(''), html, '/r', host, ledger)

  // Assert
  expect(ledger.rasterPictures).toBe(2)
})

test('a file: link with a single slash names a local file like file:///', async () => {
  // Arrange
  const host = hostWithFiles({
    '/tmp/shot.png':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  })
  const html = '<p><img src="file:/tmp/shot.png"></p>'

  // Act
  const result = await embedImages(
    page('![画面](file:/tmp/shot.png)\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result).toEqual({
    html: '<p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="></p>',
    diagnostics: [],
  })
})

test('an SVG that draws a picture by linking it stops the export: a picture shown as an image loads no link', async () => {
  // Arrange
  const svg = '<svg xmlns="http://www.w3.org/2000/svg"><image href="shot.png" width="10" height="10"/></svg>'
  const host = hostWithFiles({ '/r/pages/linked.svg': toBase64(svg) })
  const html = '<p><img src="linked.svg"></p>'

  // Act
  const result = await embedImages(page('![図](linked.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image linked.svg draws a picture it links to (shot.png), which it cannot show inside the Handout: embed that picture in the SVG',
  ])
})

test('an SVG that loads a picture through a style or an HTML image stops the export like a linked <image>', async () => {
  // Arrange
  const styled =
    '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" style="fill: url(texture.png)"/></svg>'
  const labelled =
    '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject width="10" height="10"><img xmlns="http://www.w3.org/1999/xhtml" src="shot.png"/></foreignObject></svg>'
  const host = hostWithFiles({
    '/r/pages/styled.svg': toBase64(styled),
    '/r/pages/labelled.svg': toBase64(labelled),
  })
  const html = '<p><img src="styled.svg"><img src="labelled.svg"></p>'

  // Act
  const result = await embedImages(
    page('![一](styled.svg)\n![二](labelled.svg)\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image styled.svg draws a picture it links to (texture.png), which it cannot show inside the Handout: embed that picture in the SVG',
    'page 3:2: the image labelled.svg draws a picture it links to (shot.png), which it cannot show inside the Handout: embed that picture in the SVG',
  ])
})

test('a picture written as percent-encoded data (%89PNG…) is embedded as its bytes', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="data:image/png,%89PNG%0D%0A%1A%0A"></p>'

  // Act
  const result = await embedImages(
    page('<img src="data:image/png,…">\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result).toEqual({
    html: '<p><img src="data:image/png;base64,iVBORw0KGgo="></p>',
    diagnostics: [],
  })
})

test('a key in the text of an SVG saved as UTF-16 stops the export like one in a UTF-8 SVG', async () => {
  // Arrange
  const svg = `<svg xmlns="http://www.w3.org/2000/svg"><text>${ACCESS_KEY_ID}</text></svg>`
  const utf16 = new Uint8Array([
    0xff,
    0xfe,
    ...Array.from(svg).flatMap((character) => [character.charCodeAt(0), 0]),
  ])
  const host = hostWithFiles({ '/r/pages/key.svg': bytesToBase64(utf16) })
  const html = '<p><img src="key.svg"></p>'

  // Act
  const result = await embedImages(page('![鍵](key.svg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message:
        'page 3:1: the image key.svg carries a secret shape (aws-access-key-id); remove the value from the file',
      page: 3,
      line: 1,
    },
  ])
})

test('a key at the end of a PNG text chunk stops the export even when the CRC after it starts with a letter', async () => {
  // Arrange
  const text = new TextEncoder().encode(`Comment\0${ACCESS_KEY_ID}`)
  const png = pngWith([['tEXt', text]])
  // The chunk's real CRC (0x72EF62F0) starts with "r", which runs into the key read as text
  png.set([0x72, 0xef, 0x62, 0xf0], 8 + 8 + text.length)
  const host = hostWithFiles({ '/r/pages/shot.png': bytesToBase64(png) })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image shot.png carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
  ])
})

test('a key at the start of a GIF comment stops the export even when the length byte before it is a letter', async () => {
  // Arrange
  // The comment is 65 bytes long: its length byte is "A", which runs into the key read as text
  const comment = Array.from(`${ACCESS_KEY_ID} is the deploy key`.padEnd(65, '.'), (character) =>
    character.charCodeAt(0),
  )
  const screen = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]
  const gif = new Uint8Array([...screen, 0x21, 0xfe, comment.length, ...comment, 0x00, 0x3b])
  const host = hostWithFiles({ '/r/pages/flow.gif': bytesToBase64(gif) })
  const html = '<p><img src="flow.gif"></p>'

  // Act
  const result = await embedImages(page('![流れ](flow.gif)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image flow.gif carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
  ])
})

test('a key at the start of a JPEG comment stops the export even when the length byte before it is a digit', async () => {
  // Arrange
  // 46 bytes of text: the segment's length (48, its own 2 bytes counted) ends in 0x30, "0"
  const comment = Array.from(`${ACCESS_KEY_ID} rotate`.padEnd(46, '.'), (character) =>
    character.charCodeAt(0),
  )
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xfe, 0x00, comment.length + 2, ...comment, 0xff, 0xd9])
  const host = hostWithFiles({ '/r/pages/photo.jpg': bytesToBase64(jpeg) })
  const html = '<p><img src="photo.jpg"></p>'

  // Act
  const result = await embedImages(page('![写真](photo.jpg)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image photo.jpg carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
  ])
})

/** A WebP chunk: its type, its size (one byte of it used here, little endian) and its data. */
function webpChunk(type: string, data: number[]): number[] {
  return [...Array.from(type, (character) => character.charCodeAt(0)), data.length & 0xff, 0, 0, 0, ...data]
}

test('a key at the end of a WebP chunk stops the export even when the next chunk type follows it', async () => {
  // Arrange
  const text = Array.from(`key ${ACCESS_KEY_ID}`, (character) => character.charCodeAt(0))
  const body = [
    ...Array.from('WEBP', (character) => character.charCodeAt(0)),
    ...webpChunk('XMP ', text),
    ...webpChunk('EXIF', []),
  ]
  const webp = new Uint8Array([0x52, 0x49, 0x46, 0x46, body.length & 0xff, 0, 0, 0, ...body])
  const host = hostWithFiles({ '/r/pages/shot.webp': bytesToBase64(webp) })
  const html = '<p><img src="shot.webp"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.webp)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image shot.webp carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
  ])
})

test('a key at the start of a PNG chunk cut off by the end of the file still stops the export', async () => {
  // Arrange
  const png = pngWith([['tEXt', new TextEncoder().encode(`${ACCESS_KEY_ID}\0note`)]])
  const cut = png.subarray(0, png.length - 12 - 6)
  const host = hostWithFiles({ '/r/pages/shot.png': bytesToBase64(cut) })
  const html = '<p><img src="shot.png"></p>'

  // Act
  const result = await embedImages(page('![画面](shot.png)\n'), html, '/r', host, createImageLedger())

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image shot.png carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
  ])
})

test('a screenshot an SVG label carries as an HTML image (src or srcset) is checked like one on its own', async () => {
  // Arrange
  const png = pngWith([['tEXt', new TextEncoder().encode(`Comment\0${ACCESS_KEY_ID}`)]])
  const label = (attribute: string) =>
    `<svg xmlns="http://www.w3.org/2000/svg"><foreignObject width="10" height="10"><img xmlns="http://www.w3.org/1999/xhtml" ${attribute}="data:image/png;base64,${bytesToBase64(png)}"/></foreignObject></svg>`
  const host = hostWithFiles({
    '/r/pages/src.svg': toBase64(label('src')),
    '/r/pages/srcset.svg': toBase64(label('srcset')),
  })
  const html = '<p><img src="src.svg"><img src="srcset.svg"></p>'

  // Act
  const result = await embedImages(
    page('![一](src.svg)\n![二](srcset.svg)\n'),
    html,
    '/r',
    host,
    createImageLedger(),
  )

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 3:1: the image src.svg carries a picture that carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
    'page 3:2: the image srcset.svg carries a picture that carries a secret shape (aws-access-key-id) in its metadata; save the picture again without it',
  ])
})
