import type { Row } from '@dw/protocol'
import { render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'

import { formatDuration } from './duration'
import { RowView } from './RowView'

/** Draw one Row and return its container. */
function draw(row: Row) {
  return render(<RowView row={row} />).container
}

test('shows a prompt from the HUD under a dim line naming the plugin', () => {
  // Arrange
  const row: Row = {
    kind: 'prompt',
    id: 'p',
    text: 'Open page two',
    origin: 'plugin',
    from: 'desktop-walkthrough',
  }

  // Act
  const container = draw(row)

  // Assert
  expect(container.textContent).toBe('›From the desktop-walkthrough plugin❯Open page two')
})

test('shows a peer message as one collapsed line that names the sender', () => {
  // Arrange
  const row: Row = { kind: 'prompt', id: 'p', text: 'secret body', origin: 'peer', from: 'reviewer' }

  // Act
  const container = draw(row)

  // Assert
  expect(container.textContent).toBe('›Message from @reviewer (ctrl+o to expand)')
})

test('colours the bullet of a failed task notification with the error colour', () => {
  // Arrange
  const row: Row = {
    kind: 'prompt',
    id: 'p',
    text: 'Task failed',
    origin: 'task-notification',
    status: 'failed',
  }

  // Act
  const marker = draw(row).querySelector<HTMLElement>('.marker')

  // Assert
  expect(marker?.style.color).toBe('var(--error)')
})

test('draws the bullet on every reply block and ends a summary with a dim tag', () => {
  // Arrange
  const row: Row = { kind: 'reply', id: 'r', text: 'Checking.', isFirstOfReply: false, isSummary: true }

  // Act
  const container = draw(row)

  // Assert
  expect(container.querySelector('.marker')?.textContent).toBe('⏺')
  expect(container.textContent).toBe('⏺Checking. · summary')
})

test('draws nothing for a command that printed nothing', () => {
  // Arrange
  const row: Row = {
    kind: 'command-output',
    id: 'c',
    command: 'clear',
    args: '',
    text: '(no content)',
    isErrored: false,
  }

  // Act
  const container = draw(row)

  // Assert
  expect(container.innerHTML).toBe('')
})

test('hangs the output of a slash command in the gutter, in the error colour when it failed', () => {
  // Arrange
  const row: Row = {
    kind: 'command-output',
    id: 'c',
    command: 'compact',
    args: '',
    text: 'Not enough messages',
    isErrored: true,
  }

  // Act
  draw(row)

  // Assert
  expect(screen.getByText('Not enough messages').className).toBe('reply-error')
  expect(document.querySelector('.gutter')?.textContent).toBe('  ⎿  ')
})

test('words the duration of a finished turn as the terminal does', () => {
  // Arrange
  const durations = [0, 7_400, 66_000, 3_723_000, 93_780_000]

  // Act
  const words = durations.map(formatDuration)

  // Assert
  expect(words).toEqual(['0s', '7s', '1m 6s', '1h 2m 3s', '1d 2h 3m'])
})

test('closes a turn with the dim marker, the verb and the time it took', () => {
  // Arrange
  const row: Row = { kind: 'turn-duration', id: 't', word: 'Baked', durationMs: 3_000 }

  // Act
  const container = draw(row)

  // Assert
  expect(container.textContent).toBe('✻Baked for 3s')
})

test('adds the slash command after a notice that has one', () => {
  // Arrange
  const row: Row = { kind: 'notice', id: 'n', text: 'Using Opus', command: '/model' }

  // Act
  const container = draw(row)

  // Assert
  expect(container.textContent).toBe('Using Opus · /model')
})

test("shows a line a plugin logged under the plugin's name", () => {
  // Arrange
  const row: Row = { kind: 'log', id: 'log-1', plugin: 'thinking-log', text: '✻ Comparing the two screens.' }

  // Act
  const container = draw(row)

  // Assert
  expect(container.textContent).toBe('⏺thinking-log: ✻ Comparing the two screens.')
})
