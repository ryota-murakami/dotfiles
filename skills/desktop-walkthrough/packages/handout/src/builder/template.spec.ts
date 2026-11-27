import { expect, test } from 'vitest'

import { handoutCss } from './template'

test('the Handout takes the Explainer’s CSS without the reading marks', () => {
  // Arrange
  const template = [
    '<head><style>',
    '  h1 { font-size: 1.5em; }',
    '  /* handout: reading marks begin */',
    '  .rd-mark { position: absolute; }',
    '  /* handout: reading marks end */',
    '  @media (prefers-contrast: more) { body { color: #fff; } }',
    '</style></head>',
  ].join('\n')

  // Act
  const result = handoutCss(template)

  // Assert
  expect(result).toEqual({
    ok: true,
    css: '\n  h1 { font-size: 1.5em; }\n  \n  @media (prefers-contrast: more) { body { color: #fff; } }\n',
  })
})

test('a page.html without the markers stops the export instead of shipping reading marks', () => {
  // Arrange
  const template = '<style>h1 { font-size: 1.5em; } .rd-mark { position: absolute; }</style>'

  // Act
  const result = handoutCss(template)

  // Assert
  expect(result).toEqual({ ok: false, reason: 'the reading-marks markers are missing from its <style>' })
})

test('markers in the wrong order stop the export', () => {
  // Arrange
  const template =
    '<style>/* handout: reading marks end */ .rd-mark {} /* handout: reading marks begin */</style>'

  // Act
  const result = handoutCss(template)

  // Assert
  expect(result).toEqual({ ok: false, reason: 'the reading-marks end marker comes before its begin marker' })
})

test('a page.html without a style block stops the export', () => {
  // Arrange
  const template = '<html><body></body></html>'

  // Act
  const result = handoutCss(template)

  // Assert
  expect(result).toEqual({ ok: false, reason: 'it has no <style> block' })
})
