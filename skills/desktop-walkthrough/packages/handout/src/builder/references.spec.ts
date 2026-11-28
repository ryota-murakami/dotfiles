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

test('a url() whose name is spelled with CSS escapes still counts as a load', () => {
  // Arrange
  const html = '<p><span style="background: u\\72l(data:image/png;base64,iVBORw0KGgo=)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_IMAGE'])
})

test('a style whose quoted url goes on past a backslash at the end of a line still stops the export', () => {
  // Arrange
  const html = '<p><span style="background: url(&quot;im\\\nage.png&quot;)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads image.png, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a hexadecimal escape swallows a form feed after it, as a browser does: the url( it spells is caught', () => {
  // Arrange
  const html = '<p><span style="background: u\\72\fl(x.png)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads x.png, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a picture in an image-set after a gradient option still stops the export: the set is read to its own closing parenthesis', () => {
  // Arrange
  const html =
    '<p><span style="background: image-set(linear-gradient(red, blue) 1x, &quot;shot.png&quot; 2x)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads shot.png, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('an image-set string ending in an escaped backslash closes there: a later string elsewhere in the style is no picture', () => {
  // Arrange
  const html =
    '<p><span style="background: image-set(&quot;a\\\\&quot; 1x); --label: &quot;x&quot;">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads a\\, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a url whose name holds an escaped line feed stops the export, naming the file the browser loads', () => {
  // Arrange
  const html = '<p><span style="background-image: url(&quot;im\\a age.png&quot;)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads image.png, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('an image-set string that holds an escaped line feed stops the export too', () => {
  // Arrange
  const html = '<p><span style="background: image-set(&quot;sh\\a ot.png&quot; 1x)">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads shot.png, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a diagram reference to its own marker spelled with an escaped line feed still loads nothing', () => {
  // Arrange
  const html =
    '<svg><defs><marker id="arrow"></marker></defs><path marker-end="url(&quot;\\a #arrow&quot;)"></path></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a style whose url( runs to the end of the attribute unclosed still stops the export, as CSS reads it to the end', () => {
  // Arrange
  const html = '<p><span style="background-image: url(data:image/png;base64,AAAA">一覧</span></p>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads data:image/png;base64,AAAA, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a quoted url, an image-set string and an @import string left open at the end still stop the export', () => {
  // Arrange
  const html =
    '<p><span style="background: url(&quot;open.png">一</span><span style="background: image-set(&quot;set.png">二</span></p>' +
    '<svg><style>@import "theme.css</style></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: a style loads open.png, which a Handout neither checks nor carries: show the picture with an image instead',
    'page 4: a style loads set.png, which a Handout neither checks nor carries: show the picture with an image instead',
    'page 4: a style loads theme.css, which a Handout neither checks nor carries: show the picture with an image instead',
  ])
})

test('a diagram reference to its own marker left unclosed at the end still loads nothing', () => {
  // Arrange
  const html = '<svg><defs><marker id="arrow"></marker></defs><path marker-end="url(#arrow"></path></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})

// Generated by the /gstack-ship test coverage audit (pass 1).
// Value: protects=a loaded address named in a stop message has its secret shapes masked, and embed/object/iframe loads each stop the export; fails_when=quoted() stops masking or LOADED_ATTRIBUTES loses src/data for these elements; why_new=the tests above cover only video and td background, never a secret in the address; seam=none; no_claim=the sanitizer drops these elements first in a real export (references only)
test('an embed, an object and an iframe each stop the export, and a signed address they load is never printed', () => {
  // Arrange
  // Fake credential assembled at run time so secret scanners do not flag this public file
  const signature = '0f3a'.repeat(16)
  const html =
    `<embed src="https://docs.test/a?expires=1&signature=${signature}">` +
    '<object data="/Users/u/doc.pdf"></object>' +
    '<iframe src="https://docs.test/frame"></iframe>'

  // Act
  const diagnostics = unembeddableResources(page, html)
  const messages = diagnostics.map((diagnostic) => diagnostic.message)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
    'HANDOUT_IMAGE',
    'HANDOUT_IMAGE',
    'HANDOUT_IMAGE',
  ])
  expect(messages[0]).toContain('page 4: the embed element loads https://docs.test/a?expires=1&signature=')
  expect(messages.join('\n')).not.toContain(signature)
  expect(messages[1]).toContain('the object element loads /Users/u/doc.pdf')
  expect(messages[2]).toContain('the iframe element loads https://docs.test/frame')
})

test('a diagram element that draws a file it names by href (feImage, use of another file) stops the export', () => {
  // Arrange
  const html =
    '<svg><filter id="f"><feImage href="https://tracker.test/x.png"></feImage></filter>' +
    '<use xlink:href="parts.svg#box"></use></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 4: the feImage element loads https://tracker.test/x.png, which a Handout does not carry: show the picture with an image instead',
    'page 4: the use element loads parts.svg#box, which a Handout does not carry: show the picture with an image instead',
  ])
})

test('a diagram reusing its own parts by href (#id), and its links, load nothing', () => {
  // Arrange
  const html =
    '<svg><defs><linearGradient id="g"></linearGradient><linearGradient id="h" href="#g"></linearGradient>' +
    '<symbol id="s"></symbol></defs><use href="#s"></use><a href="https://docs.test/">設計</a></svg>'

  // Act
  const diagnostics = unembeddableResources(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})
