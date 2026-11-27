import { expect, test } from 'vitest'

import type { HostReply, HostRequest } from '../contract'
import type { HostPort } from './host'
import { embedImages } from './images'

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
  source: 'pages/03-画面.md',
  markdown,
  built: 'pages/003.html',
})

test('an image beside the page is embedded, so the Handout works as one file', async () => {
  // Arrange
  const host = hostWithFiles({ '/r/pages/shot.png': 'iVBORw0KGgo=' })
  const html = '<p><img src="shot.png" alt="一覧の画面"></p>'

  // Act
  const result = await embedImages(page('![一覧の画面](shot.png)\n'), html, '/r', host)

  // Assert
  expect(result).toEqual({
    html: '<p><img src="data:image/png;base64,iVBORw0KGgo=" alt="一覧の画面"></p>',
    diagnostics: [],
  })
})

test('an image named by absolute path or file link is read from that path', async () => {
  // Arrange
  const host = hostWithFiles({ '/Users/u/Desktop/a b.jpg': '/9j/4AAQ', '/tmp/c.svg': 'PHN2Zz4=' })
  const html = '<p><img src="/Users/u/Desktop/a%20b.jpg"><img src="file:///tmp/c.svg"></p>'

  // Act
  const result = await embedImages(page(''), html, '/r', host)

  // Assert
  expect(result.html).toBe(
    '<p><img src="data:image/jpeg;base64,/9j/4AAQ"><img src="data:image/svg+xml;base64,PHN2Zz4="></p>',
  )
  expect(host.asked).toEqual(['/Users/u/Desktop/a b.jpg', '/tmp/c.svg'])
})

test('a missing image stops the export at the line that names it', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="/tmp/screenshot-1.png" alt="画面"></p>'

  // Act
  const result = await embedImages(page('# 画面\n\n![画面](/tmp/screenshot-1.png)\n'), html, '/r', host)

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_IMAGE',
      message: 'pages/03-画面.md:3: the image /tmp/screenshot-1.png could not be read: no such file',
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
  const result = await embedImages(page('![](https://cdn.test/logo.png)\n'), html, '/r', host)

  // Assert
  expect(result.diagnostics).toEqual([
    {
      code: 'HANDOUT_IMAGE',
      message: 'pages/03-画面.md:1: the image https://cdn.test/logo.png is not a local file',
      page: 3,
      line: 1,
    },
  ])
  expect(host.asked).toEqual([])
})

test('a file the Handout cannot show as an image stops the export', async () => {
  // Arrange
  const host = hostWithFiles({ '/r/pages/notes.pdf': 'JVBERi0=' })
  const html = '<p><img src="notes.pdf"></p>'

  // Act
  const result = await embedImages(page('<img src="notes.pdf">\n'), html, '/r', host)

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'pages/03-画面.md:1: the image notes.pdf is not a type the Handout embeds (png, jpg, gif, webp, avif, svg)',
  ])
})

test('a page without images goes on exactly as rendered', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html =
    '<svg id="p3-d1"><foreignObject width="70" height="24"><div>書き出す</div></foreignObject></svg>'

  // Act
  const result = await embedImages(page(''), html, '/r', host)

  // Assert
  expect(result).toEqual({ html, diagnostics: [] })
})

test('an image with a short name is located at the line that writes it as an image, not at any line with its letters', async () => {
  // Arrange
  const host = hostWithFiles({})
  const html = '<p><img src="x"></p>'

  // Act
  const result = await embedImages(page('# 画面\n\nexport const x = 1\n\n<img src="x">\n'), html, '/r', host)

  // Assert
  expect(result.diagnostics.map((diagnostic) => diagnostic.line)).toEqual([5])
})
