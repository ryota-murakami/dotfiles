import { expect, test } from 'vitest'

import { escapeHtml } from './escapeHtml'

test('a title that spells markup is written into the Handout as text, never as markup', () => {
  // Arrange
  const title = '<script>確認</script> & 結果'

  // Act
  const escaped = escapeHtml(title)

  // Assert
  expect(escaped).toBe('&#60;script&#62;確認&#60;/script&#62; &#38; 結果')
})

test('a quote in a value cannot end the attribute it is written into', () => {
  // Arrange
  const value = 'say "hi"'

  // Act
  const escaped = escapeHtml(value)

  // Assert
  expect(`<p title="${escaped}">`).toBe('<p title="say &#34;hi&#34;">')
})
