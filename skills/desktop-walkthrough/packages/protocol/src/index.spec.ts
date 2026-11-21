import { expect, test } from 'vitest'

import { galleryFixtures, liveWhileToolRuns, turnInProgress } from './fixtures'
import { liveDocumentSchema, rowSchema, transcriptDocumentSchema } from './index'

test('the Mirror accepts the transcript of a turn in progress', () => {
  // Arrange
  const document = turnInProgress

  // Act
  const parsed = transcriptDocumentSchema.safeParse(document)

  // Assert
  expect(parsed.success).toBe(true)
})

test('the Mirror refuses a transcript written for another protocol version', () => {
  // Arrange
  const document = { ...turnInProgress, v: 2 }

  // Act
  const parsed = transcriptDocumentSchema.safeParse(document)

  // Assert
  expect(parsed.success).toBe(false)
})

test('the Mirror refuses a live state whose spinner names a mode Claude Code does not have', () => {
  // Arrange
  const document = { ...liveWhileToolRuns, spinner: { word: 'Puzzling', suffix: '…', mode: 'daydreaming' } }

  // Act
  const parsed = liveDocumentSchema.safeParse(document)

  // Assert
  expect(parsed.success).toBe(false)
})

test('the Mirror accepts every Row of its gallery', () => {
  // Arrange
  const rows = galleryFixtures.flatMap((fixture) => fixture.rows)

  // Act
  const failures = rows.filter((row) => !rowSchema.safeParse(row).success)

  // Assert
  expect(failures).toEqual([])
})
