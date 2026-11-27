// @vitest-environment jsdom
// jsdom: its CSS object model reads a style sheet as WebKit's does, rule by rule
import { expect, test } from 'vitest'

import flowchart from '../builder/fixtures/flowchart.svg?raw'
import { scopedDiagramCss } from './scopedDiagramCss'

/** How many top-level rules the document's CSS parser reads in CSS. */
function ruleCount(css: string): number {
  const style = document.createElement('style')
  style.textContent = css
  document.head.append(style)
  const count = style.sheet?.cssRules.length ?? 0
  style.remove()
  return count
}

test("every rule mermaid wrote for a diagram stays: its rules scoped by the diagram's id and its keyframes", () => {
  // Arrange
  const css = /<style>(.*?)<\/style>/s.exec(flowchart.replaceAll('dw-diagram-1', 'p2-d1'))?.[1] ?? ''

  // Act
  const scoped = scopedDiagramCss(css, 'p2-d1', document)

  // Assert
  expect(ruleCount(css)).toBe(59)
  expect(ruleCount(scoped)).toBe(59)
})

test('a rule that reaches past the diagram goes: another page, the body, a sibling of the SVG, another diagram, an at-rule', () => {
  // Arrange
  const css =
    '@import url(theme.css);#p2-d1 .node{fill:red}#page-2{display:none}body{display:none}#p2-d1 + *{display:none}' +
    '#p2-d1 ~ p{color:red}#p2-d10{fill:green}@media all{#p2-d1{fill:blue}}'

  // Act
  const scoped = scopedDiagramCss(css, 'p2-d1', document)

  // Assert
  expect(scoped).toBe('#p2-d1 .node { fill: red; }')
})

test('a selector list with one selector past the diagram drops the whole rule', () => {
  // Arrange
  const css = '#p2-d1 .label, .handout-header{color:red}'

  // Act
  const scoped = scopedDiagramCss(css, 'p2-d1', document)

  // Assert
  expect(scoped).toBe('')
})

test('a comma inside :is() or an attribute and a + inside :nth-child() keep a rule inside the diagram', () => {
  // Arrange
  const css = '#p2-d1 :is(.a, .b), #p2-d1 [data-x="a,b"]{fill:red}#p2-d1 g:nth-child(2n+1){fill:blue}'

  // Act
  const scoped = scopedDiagramCss(css, 'p2-d1', document)

  // Assert
  expect(scoped).toBe(
    '#p2-d1 :is(.a, .b), #p2-d1 [data-x="a,b"] { fill: red; }\n#p2-d1 g:nth-child(2n+1) { fill: blue; }',
  )
})
