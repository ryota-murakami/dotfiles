import { turnInProgress } from '@dw/protocol/fixtures'
import { act, render, screen } from '@testing-library/react'
import { beforeEach, expect, test } from 'vitest'

import { App } from './App'
import { receiveTranscript, resetStore } from './store'

beforeEach(() => {
  resetStore()
})

test('shows the prompt of a turn the HUD handed over', () => {
  // Arrange
  render(<App />)

  // Act
  act(() => {
    receiveTranscript(turnInProgress)
  })

  // Assert
  expect(screen.getByText('run the tests').isConnected).toBe(true)
})

test('keeps the last transcript when the HUD hands over something that is not a transcript', () => {
  // Arrange
  render(<App />)
  act(() => {
    receiveTranscript(turnInProgress)
  })

  // Act
  let accepted = true
  act(() => {
    accepted = receiveTranscript({ rows: 'nonsense' })
  })

  // Assert
  expect(accepted).toBe(false)
  expect(screen.getByText('run the tests').isConnected).toBe(true)
})
