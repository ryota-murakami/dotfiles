import { turnInProgress } from '@dw/protocol/fixtures'
import { act, render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'

import { App, receive } from './App'

test('shows the prompt of a turn the HUD handed over', () => {
  // Arrange
  render(<App />)

  // Act
  act(() => {
    receive(turnInProgress)
  })

  // Assert
  expect(screen.getByText('run the tests').isConnected).toBe(true)
})

test('keeps the last transcript when the HUD hands over something that is not a document', () => {
  // Arrange
  render(<App />)
  act(() => {
    receive(turnInProgress)
  })

  // Act
  let accepted = true
  act(() => {
    accepted = receive({ rows: 'nonsense' })
  })

  // Assert
  expect(accepted).toBe(false)
  expect(screen.getByText('run the tests').isConnected).toBe(true)
})
