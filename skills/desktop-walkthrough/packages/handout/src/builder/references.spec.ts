// @vitest-environment jsdom
// jsdom: happy-dom drops the text of an SVG <style> inside a template, which WebKit keeps
import { expect, test } from 'vitest'

import { localLinks, unembeddableResources } from './references'

const page = { n: 4, title: '画面', section: '', markdown: '', built: 'pages/004.html' }

test('a video stops the export: a Handout carries pictures only, and the colleague would get a dead player', () => {
  // Arrange
  const html = '<p><video src="/Users/u/Movies/demo.mov" poster="/Users/u/poster.png" controls></video></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_IMAGE',
      message:
        'page 4: a video cannot go into a Handout, which carries pictures only: show a picture of it, or link to where it is shared',
      page: 4,
    },
  ])
})

test('a style that loads a picture stops the export: its bytes would go unchecked into the file', () => {
  // Arrange
  const html = '<p><span style="background: url(data:image/png;base64,iVBORw0KGgo=)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads data:image/png;base64,iVBORw0KGgo=, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a diagram’s own style that loads a file stops the export too', () => {
  // Arrange
  const html = '<svg><style>.node { fill: url("file:///Users/u/texture.png") }</style></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_IMAGE'])
})

test('a legacy background attribute naming a file stops the export', () => {
  // Arrange
  const html = '<table><tbody><tr><td background="/Users/u/bg.png">表</td></tr></tbody></table>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: the td element loads /Users/u/bg.png, which a Handout does not carry: show the picture with an image instead',
  ])
})

test('what a diagram points at inside itself (url(#id)) and embedded pictures pass', () => {
  // Arrange
  const html =
    '<svg><defs><marker id="arrow"></marker></defs><path marker-end="url(#arrow)"></path><image href="data:image/png;base64,iVBORw0KGgo="></image></svg>' +
    '<p><img src="data:image/png;base64,iVBORw0KGgo=" alt="画面"></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a link to a file on this Mac is a warning: the export goes on, and the agent learns the colleague cannot open it', () => {
  // Arrange
  const html = '<p><a href="file:///Users/u/notes.md">メモ</a> と <a href="02-設定.md">次のページ</a></p>'

  // Act
  const warnings = localLinks(page, html)

  // Assert
  expect(warnings).toEqual([
    {
      message: "links to file:///Users/u/notes.md, a file on this Mac: the colleague's copy cannot open it",
      page: 4,
    },
    { message: "links to 02-設定.md, a file on this Mac: the colleague's copy cannot open it", page: 4 },
  ])
})

test('links to the web, to mail and within the page pass without a warning', () => {
  // Arrange
  const html =
    '<p><a href="https://example.com/notes">設計</a><a href="mailto:team@example.com">連絡</a><a href="#設定">設定へ</a></p>'

  // Act
  const warnings = localLinks(page, html)

  // Assert
  expect(warnings).toEqual([])
})

test('an alt text that mentions url(…) is no style: the export goes on', () => {
  // Arrange
  const html =
    '<p><img src="data:image/png;base64,iVBORw0KGgo=" alt="背景は url(background.png) で指定します" title="url(x.png)"></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a style that loads a picture through image-set stops the export, as url(…) does', () => {
  // Arrange
  const html = `<p><span style="background-image: image-set('bg.png' 1x, &quot;bg@2x.png&quot; 2x)">一覧</span></p>`

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads bg.png, which a Handout neither checks nor carries: show the picture with an image instead',
    'page 4: a style loads bg@2x.png, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a diagram style that imports a style sheet stops the export', () => {
  // Arrange
  const html = '<svg><style>@import "theme.css"; .node { fill: red }</style></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_IMAGE'])
})

test('an SVG presentation attribute that points outside the diagram stops the export', () => {
  // Arrange
  const html = '<svg><rect fill="url(texture.svg#p)"></rect></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_IMAGE'])
})
