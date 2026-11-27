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

test('responsive image alternatives go: only the embedded src reaches the Handout, whatever the screen', () => {
  // Arrange
  const content =
    '<picture><source srcset="shot@2x.png 2x"><img src="data:image/png;base64,iVBORw0KGgo=" srcset="shot@2x.png 2x" alt="画面"></picture>'

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toBe('<picture><img src="data:image/png;base64,iVBORw0KGgo=" alt="画面"></picture>')
})

test("a page's own style rules go, so they cannot reach another page's diagrams; a diagram's own style stays", () => {
  // Arrange
  const content =
    '<p>本文</p><style>.diagram .nodeLabel { font-size: 40px; }</style><div class="diagram"><svg id="p2-d1"><style>#p2-d1 .node { fill: #333; }</style></svg></div>'

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toBe(
    '<p>本文</p><div class="diagram"><svg id="p2-d1"><style>#p2-d1 .node { fill: #333; }</style></svg></div>',
  )
})

test("an element of a page cannot take an id the Handout's own page needs; other ids stay", () => {
  // Arrange
  const content =
    '<div id="handout-toc">偽の目次</div><p id="page-2">偽のページ</p><span id="pageno">9/9</span><h2 id="setup">準備</h2>'

  // Act
  const sanitized = sanitizePage(content)

  // Assert
  expect(sanitized).toBe('<div>偽の目次</div><p>偽のページ</p><span>9/9</span><h2 id="setup">準備</h2>')
})
