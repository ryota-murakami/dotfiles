import { expect, test } from 'claude-code/testing'
import { chunkChars, clipText, clipValue, newPlacement, place } from './mirror'

// A fake credential assembled at run time, so secret scanners do not flag this public file
const TOKEN = ['abcdefgh', 'ijklmnop', 'qrstuvwx'].join('')

test('a short command output reaches the Mirror whole', () => {
  // Arrange
  const output = 'On branch main\nnothing to commit'

  // Act
  const carried = clipText(output)

  // Assert
  expect(carried).toBe('On branch main\nnothing to commit')
})

test('a long command output reaches the Mirror as its first lines and the size of the whole', () => {
  // Arrange
  const output = 'line 1\nline 2\nline 3\nline 4\nline 5'

  // Act
  const carried = clipText(output, 2, 1000)

  // Assert
  expect(carried).toEqual({ head: 'line 1\nline 2', lines: 5, chars: 34 })
})

test('a secret in a tool result is hidden before it reaches the Mirror', () => {
  // Arrange
  const result = { stdout: `curl -H 'Authorization: Bearer ${TOKEN}' https://api.test/me`, interrupted: false }

  // Act
  const carried = clipValue(result)

  // Assert
  expect(carried).toEqual({ stdout: "curl -H 'Authorization: Bearer •••' https://api.test/me", interrupted: false })
})

test('a long list in a tool result is cut and says how many items were left out', () => {
  // Arrange
  const lines = Array.from({ length: 203 }, (_, index) => `+${index}`)

  // Act
  const carried = clipValue({ lines }) as { lines: unknown[] }

  // Assert
  expect(carried.lines.length).toBe(201)
  expect(carried.lines[200]).toEqual({ __dwMore: 3 })
})

test('a new row goes under the rows already shown', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'prompt', 1000)
  place(placement, 'reply', 5000)

  // Act
  place(placement, 'tool', 9000)

  // Assert
  expect(placement.order).toEqual(['prompt', 'reply', 'tool'])
})

test('a row first seen in a redraw takes the place the redraw shows, between rows already known', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'a', 1000)
  place(placement, 'c', 5000)
  place(placement, 'd', 9000)

  // Act: the terminal redraws its rows top to bottom within a few milliseconds
  place(placement, 'a', 20000)
  place(placement, 'c', 20001)
  place(placement, 'x', 20002)
  place(placement, 'd', 20003)

  // Assert
  expect(placement.order).toEqual(['a', 'c', 'x', 'd'])
})

test('rows first seen at the top of a redraw go above the rows already known', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'c', 1000)
  place(placement, 'd', 5000)

  // Act
  place(placement, 'a', 20000)
  place(placement, 'b', 20001)
  place(placement, 'c', 20002)
  place(placement, 'd', 20003)

  // Assert
  expect(placement.order).toEqual(['a', 'b', 'c', 'd'])
})

test('a row that follows the redraw of one earlier row still goes last', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'a', 1000)
  place(placement, 'b', 5000)
  place(placement, 'c', 9000)

  // Act: an earlier row changes, and a new row is drawn right after it
  place(placement, 'a', 20000)
  place(placement, 'new', 20002)

  // Assert
  expect(placement.order).toEqual(['a', 'b', 'c', 'new'])
})

test('the spinner line counts streamed text, thinking and tool arguments, and nothing for the engine\'s own items', () => {
  // Arrange
  const chunks = [
    { kind: 'text', index: 0, text: 'done' },
    { kind: 'thinking', index: 1, text: 'hmm' },
    { kind: 'input', index: 2, json: '{"a":1}' },
    { kind: 'tool', index: 2, id: 'toolu_1', name: 'Bash' },
    { kind: 'engine', ref: 7 },
  ] as const

  // Act
  const chars = chunks.map(chunk => chunkChars(chunk))

  // Assert
  expect(chars).toEqual([4, 3, 7, 0, 0])
})
