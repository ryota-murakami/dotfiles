import { afterEach, expect, test } from 'vitest'

import type { HostReply, HostRequest } from '../contract'
import { readFile, renderPage, verifyInHost, webkitHost } from './host'

/** A host that answers every request with the same reply. */
const answering =
  (reply: HostReply) =>
  async (_request: HostRequest): Promise<HostReply> =>
    reply

const rendered = (page: number): HostReply => ({
  type: 'rendered',
  report: { type: 'rendered', page, diagrams: 0, errors: [], libs: [] },
  probe: null,
})

afterEach(() => {
  Reflect.deleteProperty(window, 'webkit')
})

test('the builder opened outside the renderer host says so instead of hanging', async () => {
  // Arrange
  Reflect.deleteProperty(window, 'webkit')

  // Act
  const asked = webkitHost({ type: 'read', path: '/r/pages/shot.png' })

  // Assert
  await expect(asked).rejects.toThrow(
    'the renderer host channel is missing: the builder runs only inside the host',
  )
})

test('a host reply that breaks the contract is refused before the builder uses it', async () => {
  // Arrange
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: { messageHandlers: { host: { postMessage: async () => ({ type: 'file' }) } } },
  })

  // Act
  const asked = webkitHost({ type: 'read', path: '/r/pages/shot.png' })

  // Assert
  await expect(asked).rejects.toThrow()
})

test('a host that returns the report of another page is a broken host, not a broken page', async () => {
  // Arrange
  const host = answering(rendered(3))

  // Act
  const asked = renderPage(host, 2, 'return null')

  // Assert
  await expect(asked).rejects.toThrow('the host returned the report of page 3 for page 2')
})

test('a file the host cannot read comes back as a reason, worded by the host', async () => {
  // Arrange
  const host = answering({ type: 'unreadable', message: 'permission denied' })

  // Act
  const read = await readFile(host, '/r/pages/shot.png')

  // Assert
  expect(read).toEqual({ ok: false, message: 'permission denied' })
})

test('a verification answered with another kind of reply stops the build', async () => {
  // Arrange
  const host = answering(rendered(1))

  // Act
  const asked = verifyInHost(host, '<!doctype html>', 'return null')

  // Assert
  await expect(asked).rejects.toThrow('the host answered a verify request with "rendered"')
})
