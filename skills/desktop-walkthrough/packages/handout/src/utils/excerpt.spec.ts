import { expect, test } from 'vitest'

import { excerpt } from './excerpt'

test('a label broken over lines is quoted on one line, its whitespace runs one space', () => {
  // Arrange
  const label = '利用者が\n  書き出しを押す\t'

  // Act
  const quoted = excerpt(label)

  // Assert
  expect(quoted).toBe('利用者が 書き出しを押す')
})

test('a text of exactly 60 characters is quoted whole', () => {
  // Arrange
  const text = 'x'.repeat(60)

  // Act
  const quoted = excerpt(text)

  // Assert
  expect(quoted).toBe('x'.repeat(60))
})

test('a longer text is cut at 60 characters and marked with an ellipsis', () => {
  // Arrange
  const text = 'x'.repeat(61)

  // Act
  const quoted = excerpt(text)

  // Assert
  expect(quoted).toBe(`${'x'.repeat(60)}…`)
})

test('an emoji at the cut stays whole: a message never ends in half a character', () => {
  // Arrange
  const text = `${'x'.repeat(59)}😀😀`

  // Act
  const quoted = excerpt(text)

  // Assert
  expect(quoted).toBe(`${'x'.repeat(59)}😀…`)
})

test('an empty text is quoted as empty', () => {
  // Arrange
  const text = ''

  // Act
  const quoted = excerpt(text)

  // Assert
  expect(quoted).toBe('')
})
