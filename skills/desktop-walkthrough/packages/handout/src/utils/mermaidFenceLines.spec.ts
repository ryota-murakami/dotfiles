import { expect, test } from 'vitest'

import { mermaidFenceLines } from './mermaidFenceLines'

test('each diagram is found at the line of its opening fence', () => {
  // Arrange
  const markdown = [
    '# 図',
    '',
    '```mermaid',
    'flowchart LR',
    '```',
    '',
    '~~~mermaid',
    'sequenceDiagram',
    '~~~',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([3, 7])
})

test('a diagram inside a hud-only block is not counted: the Handout never shows it', () => {
  // Arrange
  const markdown = [
    '<!-- hud-only -->',
    '```mermaid',
    'flowchart LR',
    '```',
    '<!-- /hud-only -->',
    '```mermaid',
    'flowchart TB',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([6])
})

test('a mermaid fence shown as an example inside a longer fence is no diagram', () => {
  // Arrange
  const markdown = [
    '````md',
    '```mermaid',
    'flowchart LR',
    '```',
    '````',
    '```mermaid',
    'flowchart TB',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([6])
})

test('a hud-only marker shown inside a code block does not hide the diagrams after it', () => {
  // Arrange
  const markdown = ['```html', '<!-- hud-only -->', '```', '```mermaid', 'flowchart LR', '```'].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([4])
})

test('an indented code line that looks like a fence is no fence', () => {
  // Arrange
  const markdown = [
    '    ```mermaid',
    '    flowchart LR',
    '    ```',
    '```mermaid',
    'flowchart TB',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([4])
})

test('three backticks around a word inside a line are inline code, not a fence that would hide the diagrams after it', () => {
  // Arrange
  const markdown = ['```x``` のとおりに書きます', '', '```mermaid', 'flowchart LR', '```'].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([3])
})

test('a diagram whose fence opens on a list item’s line is found, and its indented closing fence closes it', () => {
  // Arrange
  const markdown = [
    '- ```mermaid',
    '  flowchart LR',
    '  ```',
    '',
    '```mermaid',
    'sequenceDiagram',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([1, 5])
})

test('a fence inside a nested list item closes at its own indentation', () => {
  // Arrange
  const markdown = [
    '1. 手順',
    '   - ```bash',
    '     echo 書き出す',
    '     ```',
    '',
    '```mermaid',
    'flowchart TB',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([6])
})

test('a page saved with Windows line endings finds its diagrams the same way', () => {
  // Arrange
  const markdown = ['```mermaid', 'flowchart LR', '```', '', '```mermaid', 'flowchart TB', '```'].join('\r\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([1, 5])
})

test('a diagram in a quote is found, and its quoted closing fence closes it', () => {
  // Arrange
  const markdown = [
    '> ```mermaid',
    '> flowchart LR',
    '> ```',
    '',
    '```mermaid',
    'sequenceDiagram',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([1, 5])
})

test('a quoted line inside an unquoted fence is code, not its closing fence', () => {
  // Arrange
  const markdown = ['```markdown', '> ```', '```', '', '```mermaid', 'flowchart TB', '```'].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([5])
})

test('a long run of quote markers that opens no fence is read at once, not by trying every way to split it', () => {
  // Arrange
  const markdown = `${'> '.repeat(40)}x\n${'-  '.repeat(40)}x\n\n\`\`\`mermaid\nflowchart LR\n\`\`\``
  const started = performance.now()

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([4])
  expect(performance.now() - started).toBeLessThan(200)
})

test('a fence ends where its quote or list item ends, so the diagram after it is found at its line', () => {
  // Arrange
  const markdown = [
    '> ```',
    '> 引用の中',
    '引用の外',
    '- ```',
    '  項目の中',
    'リストの外',
    '```mermaid',
    'flowchart LR',
    '```',
  ].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([7])
})

test('a tab before a would-be closing fence is four columns: the fence stays open and hides the diagram after it', () => {
  // Arrange
  const markdown = ['```text', '\t```', '```mermaid', 'flowchart LR', '```'].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([])
})

test('a fence in a nested quote ends where the inner quote does: the diagram in the outer quote is found', () => {
  // Arrange
  const markdown = ['> > ```text', '> > 内側の引用', '> ```mermaid', '> flowchart LR', '> ```'].join('\n')

  // Act
  const lines = mermaidFenceLines(markdown)

  // Assert
  expect(lines).toEqual([3])
})
