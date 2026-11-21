import type { Row } from '@dw/protocol'
import { afterEach, expect, test } from 'vitest'

import { currentTranscript, receiveTranscript, resetStore } from './store'

afterEach(resetStore)

/** A Transcript document of the given Rows. */
const document = (rows: Row[]) => ({ v: 1, sessionId: 'session-1', dropped: 0, rows })

test('keeps a Row that did not change as it was when a new Transcript arrives', () => {
  // Arrange
  const reply: Row = { kind: 'reply', id: 'r1', text: 'Tests pass.', isFirstOfReply: true }
  const running: Row = {
    kind: 'tool',
    id: 't1',
    tool: 'Bash',
    input: { command: 'pnpm test' },
    isRunning: true,
    isErrored: false,
    isInterrupted: false,
  }
  receiveTranscript(document([reply, running]))
  const before = currentTranscript()?.rows ?? []

  // Act: the same reply read again from JSON, and the call now done
  const isAccepted = receiveTranscript(
    document([{ ...reply }, { ...running, isRunning: false, output: { stdout: 'ok', stderr: '' } }]),
  )
  const after = currentTranscript()?.rows ?? []

  // Assert
  expect(isAccepted).toBe(true)
  expect(after[0]).toBe(before[0])
  expect(after[1]).not.toBe(before[1])
  expect(after[1]).toEqual({ ...running, isRunning: false, output: { stdout: 'ok', stderr: '' } })
})

test('refuses a Transcript with a Row it does not know and keeps the last good one', () => {
  // Arrange
  const reply: Row = { kind: 'reply', id: 'r1', text: 'Tests pass.', isFirstOfReply: true }
  receiveTranscript(document([reply]))

  // Act
  const isAccepted = receiveTranscript({
    v: 1,
    sessionId: 'session-1',
    dropped: 0,
    rows: [{ kind: 'hologram', id: 'x' }],
  })

  // Assert
  expect(isAccepted).toBe(false)
  expect(currentTranscript()?.rows).toEqual([reply])
})
