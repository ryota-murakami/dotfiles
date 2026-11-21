import { expect, test } from 'vitest'

import { turnInProgress } from './fixtures'
import { mirrorDocumentSchema } from './index'

test('the Mirror accepts a document of a turn in progress', () => {
  // Arrange
  const document = turnInProgress

  // Act
  const parsed = mirrorDocumentSchema.safeParse(document)

  // Assert
  expect(parsed.success).toBe(true)
})

test('the Mirror refuses a document written for another protocol version', () => {
  // Arrange
  const document = { ...turnInProgress, v: 2 }

  // Act
  const parsed = mirrorDocumentSchema.safeParse(document)

  // Assert
  expect(parsed.success).toBe(false)
})
