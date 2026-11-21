import { render } from '@testing-library/react'
import { expect, test } from 'vitest'

import { Markdown } from './Markdown'
import { layoutTable } from './tableLayout'

/** Text of every block the renderer drew, one string per list item or paragraph. */
function textOf(source: string, mode: 'reply' | 'prompt' = 'reply') {
  const { container } = render(<Markdown source={source} mode={mode} />)
  return container
}

test('numbers nested ordered lists 1. then a. then i. as the terminal does', () => {
  // Arrange
  const source = '1. top\n   1. middle\n      1. bottom'

  // Act
  const markers = [...textOf(source).querySelectorAll('.md-marker')].map((marker) => marker.textContent)

  // Assert
  expect(markers).toEqual(['1.', 'a.', 'i.'])
})

test('draws every unordered item with a dash and a task item with its box', () => {
  // Arrange
  const source = '- plain\n- [x] done\n- [ ] open'

  // Act
  const container = textOf(source)

  // Assert
  expect([...container.querySelectorAll('.md-marker')].map((marker) => marker.textContent)).toEqual([
    '-',
    '-',
    '-',
  ])
  expect(container.textContent).toContain('[x] done')
  expect(container.textContent).toContain('[ ] open')
})

test('keeps a pipe inside inline code in its table cell', () => {
  // Arrange
  const source = '| a | b |\n|---|---|\n| `x|y` | z |'

  // Act
  const cells = [...textOf(source).querySelectorAll('.tcell')].map((cell) => cell.textContent)

  // Assert
  expect(cells).toEqual(['a', 'b', 'x|y', 'z'])
})

test('shows a link with an unsafe scheme as text, never as a clickable link', () => {
  // Arrange
  const source = '[click](javascript:alert(1))'

  // Act
  const container = textOf(source)

  // Assert
  expect(container.querySelector('a')).toBeNull()
  expect(container.textContent).toBe('click (javascript:alert(1))')
})

test('leaves a table literal in a prompt', () => {
  // Arrange
  const source = '| a | b |\n|---|---|\n| 1 | 2 |'

  // Act
  const container = textOf(source, 'prompt')

  // Assert
  expect(container.querySelector('.md-table')).toBeNull()
  expect(container.textContent).toContain('| a | b |')
})

test('puts a dim label above a code fence whose language is unknown', () => {
  // Arrange
  const source = '```mermaid\ngraph TD\n```'

  // Act
  const container = textOf(source)

  // Assert
  expect(container.querySelector('.dim')?.textContent).toBe('mermaid')
  expect(container.querySelector('pre')?.textContent).toBe('graph TD')
})

test('keeps a table as a grid when it fits and falls back to lines per column when a cell needs five lines', () => {
  // Arrange
  const rows = [
    ['Kind', 'Colour'],
    ['prompt', 'grey'],
  ]
  const tall = [
    ['Name', 'Text'],
    ['a', 'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen'],
  ]

  // Act
  const roomy = layoutTable(rows, 60)
  const cramped = layoutTable(tall, 24)

  // Assert
  expect(roomy).toEqual({ kind: 'grid', widths: [6, 6] })
  expect(cramped).toEqual({ kind: 'vertical' })
})
