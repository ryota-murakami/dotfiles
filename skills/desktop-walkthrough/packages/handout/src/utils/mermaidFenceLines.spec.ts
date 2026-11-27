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
