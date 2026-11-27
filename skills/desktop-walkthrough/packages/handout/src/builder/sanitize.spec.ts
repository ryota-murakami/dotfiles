// @vitest-environment jsdom
import flowchart from './fixtures/flowchart.svg?raw'
import sequence from './fixtures/sequence.svg?raw'
import { expect, test } from 'vitest'

import { diagramLabels, sanitizePage } from './sanitize'

// The fixtures are mermaid 12.2.0's output for fixtures/hud-golden (page 2), captured from the real
// page.html in a WebKit view: flowchart labels are HTML inside <foreignObject>, sequence labels SVG <text>.

test('flowchart labels survive sanitizing word for word (DOMPurify drops foreignObject by default)', () => {
  // Arrange
  const content = `<div class="diagram">${flowchart}</div>`

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(diagramLabels(sanitized)).toEqual(diagramLabels(content))
  expect(diagramLabels(sanitized)[0]?.labels).toEqual([
    '管理者',
    '閲覧者',
    '利用者が書き出しを押す',
    '役割は?',
    '書き出す',
    '403 を返す',
  ])
})

test('sequence diagram labels survive sanitizing word for word', () => {
  // Arrange
  const content = `<div class="diagram">${sequence}</div>`

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(diagramLabels(sanitized)).toEqual(diagramLabels(content))
})

test("a diagram keeps the style mermaid drew it with, so its colours reach the colleague's screen", () => {
  // Arrange
  const content = `<div class="diagram">${flowchart}</div>`

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toContain('<style>')
  expect(sanitized).toContain('fill:')
})

test('an image whose onerror would run in the recipient browser loses the handler', () => {
  // Arrange
  const content = '<p>本文 <img src="data:image/png;base64,AAAA" onerror="alert(1)"></p>'

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toBe('<p>本文 <img src="data:image/png;base64,AAAA"></p>')
})

test('scripts, javascript: links and frames never reach the Handout', () => {
  // Arrange
  const content = [
    '<script>alert(1)</script>',
    '<a href="javascript:alert(1)">押す</a>',
    '<iframe src="https://evil.test"></iframe>',
    '<p>残る本文</p>',
  ].join('')

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toBe('<a>押す</a><p>残る本文</p>')
})

test('a link to the web opens in a new tab, so the reader keeps their page', () => {
  // Arrange
  const content = '<p><a href="https://example.com/notes">設計メモ</a></p>'

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toBe(
    '<p><a href="https://example.com/notes" target="_blank" rel="noopener noreferrer">設計メモ</a></p>',
  )
})
