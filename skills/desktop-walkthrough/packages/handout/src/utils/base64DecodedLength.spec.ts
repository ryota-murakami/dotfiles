import { expect, test } from 'vitest'

import { base64DecodedLength } from './base64DecodedLength'

test('padding is not counted: a picture of exactly the limit is not taken for a larger one', () => {
  // Arrange
  const cases = ['aGk=', 'aGVsbG8=', 'aGVsbA==', 'aGVs', 'aGk']

  // Act
  const lengths = cases.map(base64DecodedLength)

  // Assert
  expect(lengths).toEqual([2, 5, 4, 3, 2])
})
