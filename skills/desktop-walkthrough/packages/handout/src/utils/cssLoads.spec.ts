import { expect, test } from 'vitest'

import { cssLoads } from './cssLoads'

test('a url spelled with CSS escapes is found like a plain one', () => {
  // Arrange
  const css = 'a { background: u\\72l(one.png) } b { background: \\55 RL("two.png") }'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['one.png', 'two.png'])
})

test('the strings of an image-set and of @import load too; a reference within the document loads nothing', () => {
  // Arrange
  const css =
    '@import "theme.css"; a { fill: url(#gradient); background: image-set("small.png" 1x, url(large.png) 2x) }'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['large.png', 'small.png', 'theme.css'])
})

test('a url that is never closed is read to the end of the text, where CSS ends it', () => {
  // Arrange
  const css = 'a { background: url("open.png'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['open.png'])
})

test('a target loses the tabs and line feeds a URL reader drops, escaped ones included', () => {
  // Arrange
  const css = 'a { background: url("im\\a age.png") } b { background: url(da\tta:image/png;base64,iVBOR) }'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['image.png', 'data:image/png;base64,iVBOR'])
})

test('an @import whose string follows at once or after a comment loads like one after a space', () => {
  // Arrange
  const css = '@import/**/"theme.css"; @import"print.css"; @import /* "left-out.css" */ url(third.css);'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['third.css', 'theme.css', 'print.css'])
})

test('an escaped quote is part of a target and never ends it: the picture is still found', () => {
  // Arrange
  const css = 'a { background: url("\\22 picture.png") } b { background: url(clo\\29 sed.png) }'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['"picture.png', 'clo)sed.png'])
})

test('a no-break space before a # stays, so the target is an address to load, not a marker of the document', () => {
  // Arrange
  const css = 'a { fill: url("\\a0 #arrow") } b { fill: url("\\a #marker") }'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual([' #arrow'])
})

test('a parenthesis inside a comment does not end an image-set: its picture is still found', () => {
  // Arrange
  const css = 'a { background: image-set(/* ) */ "https://example.test/p.png" 1x) }'

  // Act
  const loads = cssLoads(css)

  // Assert
  expect(loads).toEqual(['https://example.test/p.png'])
})
