import { expect, test } from 'vitest'

import { judgeVerification } from './verify'

const expected = [{ id: 'p2-d1', labels: ['管理者', '閲覧者', '書き出す'] }]
const working = {
  ready: true,
  pages: 3,
  pageNumber: '1/3',
  secondShown: true,
  diagrams: [{ id: 'p2-d1', labels: ['管理者', '閲覧者', '書き出す'] }],
  brokenImages: [],
}

test('a Handout that works as checked passes verification', () => {
  // Arrange
  const check = working

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a controller blocked by the CSP fails verification, so a broken file is never published', () => {
  // Arrange
  const check = { ...working, ready: false, pageNumber: '', secondShown: null }

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_VERIFY',
      message: "the finished Handout's controller did not run when it was opened (its CSP may block it)",
    },
  ])
})

test('a sanitizer that dropped labels fails verification, naming the diagram and the lost labels', () => {
  // Arrange
  const check = { ...working, diagrams: [{ id: 'p2-d1', labels: [] }] }

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_VERIFY',
      message: 'the finished Handout lost labels of diagram 1 on page 2: 「管理者」「閲覧者」「書き出す」',
      page: 2,
      diagram: 1,
    },
  ])
})

test('a diagram missing from the finished file fails verification', () => {
  // Arrange
  const check = { ...working, diagrams: [] }

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([
    { code: 'HANDOUT_VERIFY', message: 'the finished Handout lost diagram 1 on page 2', page: 2, diagram: 1 },
  ])
})

test('a Handout whose #2 does not open page 2 fails verification', () => {
  // Arrange
  const check = { ...working, secondShown: false }

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([
    { code: 'HANDOUT_VERIFY', message: 'the finished Handout did not open page 2 for #2' },
  ])
})

test('a header that does not count the pages fails verification', () => {
  // Arrange
  const check = { ...working, pageNumber: '1/2' }

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([
    { code: 'HANDOUT_VERIFY', message: 'the finished Handout shows "1/2" in its header instead of 1/3' },
  ])
})

test('a one-page Handout is not asked to open a page 2', () => {
  // Arrange
  const check = {
    ready: true,
    pages: 1,
    pageNumber: '1/1',
    secondShown: null,
    diagrams: [],
    brokenImages: [],
  }

  // Act
  const diagnostics = judgeVerification([], check, 1)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a picture the finished file cannot show fails the export, naming its page and position', () => {
  // Arrange
  const check = { ...working, brokenImages: [{ page: 2, image: 3 }] }

  // Act
  const diagnostics = judgeVerification(expected, check, 3)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_IMAGE',
      message:
        'page 2: picture 3 does not show in the finished Handout: its bytes are a broken or cut-off picture; save it again, then export again',
      page: 2,
    },
  ])
})
