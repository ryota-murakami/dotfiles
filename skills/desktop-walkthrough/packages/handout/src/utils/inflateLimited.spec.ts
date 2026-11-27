import { deflateSync } from 'node:zlib'

import { expect, test } from 'vitest'

import { inflateLimited } from './inflateLimited'

test('compressed text is inflated to its bytes', async () => {
  // Arrange
  const compressed = deflateSync(new TextEncoder().encode('書き出しの設定'))

  // Act
  const result = await inflateLimited(compressed, 1_000)

  // Assert
  expect(result.ok && new TextDecoder().decode(result.bytes)).toBe('書き出しの設定')
})

test('compressed text that inflates past the limit is refused once it passes it', async () => {
  // Arrange
  const compressed = deflateSync(new Uint8Array(64 * 1024))

  // Act
  const result = await inflateLimited(compressed, 1_024)

  // Assert
  expect(result).toEqual({ ok: false, reason: 'too-large' })
})

test('bytes that are no zlib data are refused as broken, never thrown', async () => {
  // Arrange
  const compressed = new Uint8Array([1, 2, 3, 4])

  // Act
  const result = await inflateLimited(compressed, 1_000)

  // Assert
  expect(result).toEqual({ ok: false, reason: 'broken' })
})
