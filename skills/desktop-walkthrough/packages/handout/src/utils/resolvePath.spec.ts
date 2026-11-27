import { expect, test } from 'vitest'

import { resolvePath } from './resolvePath'

test('an image beside the page resolves into the Record pages folder', () => {
  // Arrange
  const pagesFolder = '/r/pages'

  // Act
  const path = resolvePath(pagesFolder, 'shot.png')

  // Assert
  expect(path).toBe('/r/pages/shot.png')
})

test('"." and ".." fold the way the file system reads them', () => {
  // Arrange
  const pagesFolder = '/r/pages'

  // Act
  const paths = [resolvePath(pagesFolder, './img//a.png'), resolvePath(pagesFolder, '../assets/b.png')]

  // Assert
  expect(paths).toEqual(['/r/pages/img/a.png', '/r/assets/b.png'])
})

test('a path climbing above the root stops at the root, as the file system does', () => {
  // Arrange
  const pagesFolder = '/r/pages'

  // Act
  const path = resolvePath(pagesFolder, '../../../../tmp/c.png')

  // Assert
  expect(path).toBe('/tmp/c.png')
})
