import { expect, test } from 'vitest'

import { THEME_COLOR_NAMES } from './theme'

// Vitest does not process CSS, so the stylesheet is read as raw text through the bundler's glob
const files = import.meta.glob('./theme.css', { query: '?raw', import: 'default', eager: true })
const themeCss = String(files['./theme.css'])

test('gives every theme colour name a value in the theme stylesheet', () => {
  // Arrange
  const names = THEME_COLOR_NAMES

  // Act
  const missing = names.filter((name) => !new RegExp(`--${name}:\\s*rgb`).test(themeCss))

  // Assert
  expect(missing).toEqual([])
})
