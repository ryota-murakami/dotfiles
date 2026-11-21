import type { LiveDocument } from '@dw/protocol'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'

import { LiveArea } from './LiveArea'

const TURN_STARTED_AT = Date.UTC(2026, 10, 22, 12, 0, 0)

/** A busy live document of a turn that began at {@link TURN_STARTED_AT}. */
function busy(fields: Partial<LiveDocument>): LiveDocument {
  return {
    v: 1,
    isBusy: true,
    startedAt: TURN_STARTED_AT,
    spinner: { word: 'Puzzling', suffix: '…', mode: 'responding' },
    hint: 'esc to interrupt',
    ...fields,
  }
}

/** What the page has told the HUD since the last reset, without the `ready` message. */
function posted() {
  return window.dwMirrorPosted ?? []
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(TURN_STARTED_AT)
  window.dwMirrorPosted = []
})

afterEach(() => {
  vi.useRealTimers()
})

test('shows no spinner line when the HUD names no spinner, even while a turn runs', () => {
  // Arrange
  const live = busy({})
  const { spinner: _spinner, ...withoutSpinner } = live

  // Act
  const { container } = render(<LiveArea live={withoutSpinner} />)

  // Assert
  expect(container.querySelector('.spinner-line')).toBeNull()
})

test('shows the word the terminal shows with its ellipsis', () => {
  // Arrange
  const live = busy({ spinner: { word: 'Wrangling', suffix: '…', mode: 'responding' } })

  // Act
  const { container } = render(<LiveArea live={live} />)

  // Assert
  expect(container.querySelector('.spinner-text')?.textContent).toBe('Wrangling… ')
})

test('shows the elapsed time and a quarter of the response length as tokens', () => {
  // Arrange
  const live = busy({ responseLength: 20_800 })
  const { container } = render(<LiveArea live={live} />)

  // Act
  act(() => {
    vi.advanceTimersByTime(40_000)
  })

  // Assert
  expect(container.querySelector('.spinner-text')?.textContent).toBe('Puzzling… (40s · ↓ 5.2k tokens)')
})

test('counts the token figure up when the response grows instead of jumping', () => {
  // Arrange
  const { container, rerender } = render(<LiveArea live={busy({ responseLength: 400 })} />)

  // Act
  rerender(<LiveArea live={busy({ responseLength: 600 })} />)
  act(() => {
    vi.advanceTimersByTime(100)
  })
  const midway = container.querySelector('.spinner-text')?.textContent
  act(() => {
    vi.advanceTimersByTime(3000)
  })
  const settled = container.querySelector('.spinner-text')?.textContent

  // Assert
  expect(midway).toBe('Puzzling… (0s · ↓ 118 tokens)')
  expect(settled).toBe('Puzzling… (3s · ↓ 150 tokens)')
})

test('shows an up arrow while the request is being sent', () => {
  // Arrange
  const live = busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'requesting' }, responseLength: 400 })

  // Act
  const { container } = render(<LiveArea live={live} />)

  // Assert
  expect(container.querySelector('.spinner-text')?.textContent).toBe('Puzzling… (0s · ↑ 100 tokens)')
})

test('shows the time alone once a silent turn has lasted sixteen seconds', () => {
  // Arrange
  const { container } = render(
    <LiveArea live={busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'requesting' } })} />,
  )

  // Act
  act(() => {
    vi.advanceTimersByTime(15_000)
  })
  const before = container.querySelector('.spinner-text')?.textContent
  act(() => {
    vi.advanceTimersByTime(2_000)
  })
  const after = container.querySelector('.spinner-text')?.textContent

  // Assert
  expect(before).toBe('Puzzling… ')
  expect(after).toBe('Puzzling… (17s)')
})

test('names the thinking by how long it has lasted and the effort of the turn', () => {
  // Arrange
  const thinking = busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'thinking' }, effort: 'max' })
  const { container } = render(<LiveArea live={thinking} />)

  // Act
  const atStart = container.querySelector('.spinner-text')?.textContent
  act(() => {
    vi.advanceTimersByTime(12_000)
  })
  const after12 = container.querySelector('.spinner-text')?.textContent

  // Assert
  expect(atStart).toBe('Puzzling… (0s · thinking with max effort)')
  expect(after12).toBe('Puzzling… (12s · still thinking with max effort)')
})

test('says how long the thinking took for two seconds after it ends and then stops saying it', () => {
  // Arrange
  const thinking = busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'thinking' } })
  const { container, rerender } = render(<LiveArea live={thinking} />)
  act(() => {
    vi.advanceTimersByTime(8_000)
  })

  // Act
  rerender(<LiveArea live={busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'responding' } })} />)
  const justAfter = container.querySelector('.spinner-text')?.textContent
  act(() => {
    vi.advanceTimersByTime(2_500)
  })
  const later = container.querySelector('.spinner-text')?.textContent

  // Assert
  expect(justAfter).toBe('Puzzling… (8s · thought for 8s)')
  expect(later).toBe('Puzzling… ')
})

test('turns the spinner red after twenty seconds without new text and back when text arrives', () => {
  // Arrange
  const { container, rerender } = render(<LiveArea live={busy({ responseLength: 400 })} />)

  // Act
  act(() => {
    vi.advanceTimersByTime(30_000)
  })
  const stalled = container.querySelector('.spinner-line')?.getAttribute('data-stall')
  rerender(<LiveArea live={busy({ responseLength: 800 })} />)
  const recovered = container.querySelector('.spinner-line')?.getAttribute('data-stall')

  // Assert
  expect(stalled).toBe('1')
  expect(recovered).toBe('0')
})

test('does not turn red while a tool runs, however quiet it is', () => {
  // Arrange
  const live = busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'tool-use' }, responseLength: 400 })
  const { container } = render(<LiveArea live={live} />)

  // Act
  act(() => {
    vi.advanceTimersByTime(60_000)
  })

  // Assert
  expect(container.querySelector('.spinner-line')?.getAttribute('data-stall')).toBe('0')
})

test('shows the terminal hint and the mode labels under the box', () => {
  // Arrange
  const live = busy({
    hint: '⏵⏵ bypass permissions on · esc to interrupt',
    modes: ['focus', 'memory paused'],
  })

  // Act
  const { container } = render(<LiveArea live={live} />)

  // Assert
  expect(container.querySelector('.footer-hint')?.textContent).toBe(
    '⏵⏵ bypass permissions on · esc to interrupt',
  )
  expect(container.querySelector('.footer-modes')?.textContent).toBe('focus · memory paused')
})

test('hides the hint about interrupting while the box holds a draft and brings it back when emptied', () => {
  // Arrange
  const { container } = render(<LiveArea live={busy({ hint: '⏵⏵ accept edits on · esc to interrupt' })} />)
  const box = screen.getByLabelText('Prompt')

  // Act
  fireEvent.change(box, { target: { value: 'draft' } })
  const withDraft = container.querySelector('.footer-hint')?.textContent
  fireEvent.change(box, { target: { value: '' } })
  const emptied = container.querySelector('.footer-hint')?.textContent

  // Assert
  expect(withDraft).toBe('⏵⏵ accept edits on')
  expect(emptied).toBe('⏵⏵ accept edits on · esc to interrupt')
})

test('window.dwMirror.focusInput puts the keyboard in the box', async () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const { installHost } = await import('../host')
  installHost()

  // Act
  act(() => {
    window.dwMirror?.focusInput()
  })

  // Assert
  expect(document.activeElement).toBe(screen.getByLabelText('Prompt'))
})

test('tells the HUD when the box takes and loses the keyboard', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText('Prompt')

  // Act
  fireEvent.focus(box)
  fireEvent.blur(box)

  // Assert
  expect(posted()).toEqual([
    { type: 'focus', isFocused: true },
    { type: 'focus', isFocused: false },
  ])
})

test('tells the HUD about a draft once when the box goes from empty to not empty, not on every key', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText('Prompt')

  // Act
  fireEvent.change(box, { target: { value: 'h' } })
  fireEvent.change(box, { target: { value: 'he' } })
  fireEvent.change(box, { target: { value: 'hel' } })
  fireEvent.change(box, { target: { value: '' } })

  // Assert
  expect(posted()).toEqual([
    { type: 'draft', hasDraft: true },
    { type: 'draft', hasDraft: false },
  ])
})

test('Enter sends the prompt and empties the box', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText<HTMLTextAreaElement>('Prompt')
  fireEvent.change(box, { target: { value: 'run the tests' } })
  window.dwMirrorPosted = []

  // Act
  fireEvent.keyDown(box, { key: 'Enter' })

  // Assert
  expect(posted()).toEqual([
    { type: 'submit', text: 'run the tests' },
    { type: 'draft', hasDraft: false },
  ])
  expect(box.value).toBe('')
})

test('Enter in an empty box sends nothing', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText('Prompt')

  // Act
  fireEvent.keyDown(box, { key: 'Enter' })

  // Assert
  expect(posted()).toEqual([])
})

test('Enter while converting Japanese text does not send the prompt', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText<HTMLTextAreaElement>('Prompt')
  fireEvent.change(box, { target: { value: 'にほんご' } })
  window.dwMirrorPosted = []

  // Act
  fireEvent.keyDown(box, { key: 'Enter', isComposing: true })
  fireEvent.keyDown(box, { key: 'Enter', keyCode: 229 })

  // Assert
  expect(posted()).toEqual([])
  expect(box.value).toBe('にほんご')
})

test('Shift+Enter does not send the prompt', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText('Prompt')
  fireEvent.change(box, { target: { value: 'line one' } })
  window.dwMirrorPosted = []

  // Act
  fireEvent.keyDown(box, { key: 'Enter', shiftKey: true })

  // Assert
  expect(posted()).toEqual([])
})

test('Option+Enter adds a new line instead of sending', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText<HTMLTextAreaElement>('Prompt')
  fireEvent.change(box, { target: { value: 'one' } })
  box.setSelectionRange(3, 3)
  window.dwMirrorPosted = []

  // Act
  fireEvent.keyDown(box, { key: 'Enter', altKey: true })

  // Assert
  expect(box.value).toBe('one\n')
  expect(posted()).toEqual([])
})

test('Esc on an empty box stops the running turn', () => {
  // Arrange
  render(<LiveArea live={busy({})} />)

  // Act
  fireEvent.keyDown(screen.getByLabelText('Prompt'), { key: 'Escape' })

  // Assert
  expect(posted()).toEqual([{ type: 'interrupt' }])
})

test('Esc on an empty box gives the keyboard back when nothing runs', () => {
  // Arrange
  render(<LiveArea live={{ v: 1, isBusy: false }} />)

  // Act
  fireEvent.keyDown(screen.getByLabelText('Prompt'), { key: 'Escape' })

  // Assert
  expect(posted()).toEqual([{ type: 'release' }])
})

test('Esc on a box with text leaves the text alone and stops nothing', () => {
  // Arrange
  render(<LiveArea live={busy({})} />)
  const box = screen.getByLabelText<HTMLTextAreaElement>('Prompt')
  fireEvent.change(box, { target: { value: 'half written' } })
  window.dwMirrorPosted = []

  // Act
  fireEvent.keyDown(box, { key: 'Escape' })

  // Assert
  expect(posted()).toEqual([])
  expect(box.value).toBe('half written')
})

test('Up and Down walk through the prompts sent from this page and back to the draft', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText<HTMLTextAreaElement>('Prompt')
  for (const text of ['first', 'second']) {
    fireEvent.change(box, { target: { value: text } })
    fireEvent.keyDown(box, { key: 'Enter' })
  }
  fireEvent.change(box, { target: { value: 'typing' } })

  // Act
  fireEvent.keyDown(box, { key: 'ArrowUp' })
  const afterUp1 = box.value
  fireEvent.keyDown(box, { key: 'ArrowUp' })
  const afterUp2 = box.value
  fireEvent.keyDown(box, { key: 'ArrowDown' })
  const afterDown1 = box.value
  fireEvent.keyDown(box, { key: 'ArrowDown' })
  const afterDown2 = box.value

  // Assert
  expect([afterUp1, afterUp2, afterDown1, afterDown2]).toEqual(['second', 'first', 'second', 'typing'])
})

test('Up does not leave a text of several lines: the arrow moves the caret', () => {
  // Arrange
  render(<LiveArea live={undefined} />)
  const box = screen.getByLabelText<HTMLTextAreaElement>('Prompt')
  fireEvent.change(box, { target: { value: 'sent' } })
  fireEvent.keyDown(box, { key: 'Enter' })
  fireEvent.change(box, { target: { value: 'one\ntwo' } })

  // Act
  fireEvent.keyDown(box, { key: 'ArrowUp' })

  // Assert
  expect(box.value).toBe('one\ntwo')
})
