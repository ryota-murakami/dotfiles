import { useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent } from 'react'

import { post } from '../host'
import { registerInput } from './inputHandle'
import { PromptHistory } from './PromptHistory'

/** A line of `─` longer than any panel; the box clips it to its width, as a terminal fills its row. */
const RULE = '─'.repeat(600)

/**
 * Make a textarea as tall as its text.
 *
 * @param area - The Input box's textarea.
 */
function grow(area: HTMLTextAreaElement) {
  area.style.height = 'auto'
  // A renderer without layout reports 0: leave the height to the row attribute
  if (area.scrollHeight > 0) area.style.height = `${area.scrollHeight}px`
}

/**
 * One rule of the Input box: a full-width row of `─`.
 *
 * Why it exists: the terminal draws the box as two rules, so the Mirror draws the same glyph and
 * lets the cells line up like a terminal's. Rendered twice by {@link InputBox}.
 */
function Rule() {
  return (
    <div className="input-rule" aria-hidden>
      {RULE}
    </div>
  )
}

/** Insert a line break at the caret (or replace the selection), through the textarea so undo works. */
function insertNewline(area: HTMLTextAreaElement, removeBackslash: boolean) {
  const start = removeBackslash ? area.selectionStart - 1 : area.selectionStart
  area.setRangeText('\n', start, area.selectionEnd, 'end')
  area.dispatchEvent(new Event('input', { bubbles: true }))
}

/**
 * The Input box: two rules around a `❯` marker and a real textarea that grows with its text.
 *
 * Why it exists: the user writes a Prompt here, in Japanese through an input method or by dictation
 * into the focused element, which is why it is a native textarea styled like the terminal's input
 * and not a key handler of our own. Rendered by {@link LiveArea}.
 *
 * Enter sends (never while an input method composes, where it confirms the conversion); Shift+Enter,
 * Option+Enter and a backslash before Enter make a new line; Esc on an empty box interrupts the
 * running turn or gives the keyboard back; Up and Down walk through the prompts sent from the page
 * while the text is a single line. The HUD is told about focus, about the box going from empty to
 * not empty and back, and about each sent Prompt through {@link post}.
 *
 * @param props.isBusy - True while a turn runs: Esc on an empty box interrupts instead of releasing.
 * @param props.placeholder - Dim text shown while the box is empty, when there is one to show.
 * @param props.onDraftChange - Called when the box goes from empty to not empty and back.
 */
export function InputBox({
  isBusy,
  placeholder,
  onDraftChange,
}: {
  isBusy: boolean
  placeholder?: string
  onDraftChange?: (hasDraft: boolean) => void
}) {
  const [value, setValue] = useState('')
  const areaRef = useRef<HTMLTextAreaElement>(null)
  const history = useRef<PromptHistory>(null)
  history.current ??= new PromptHistory()
  const postedDraft = useRef(false)
  const caretAtEnd = useRef(false)

  // Grow with the text: as many rows as it wraps to
  useLayoutEffect(() => {
    const area = areaRef.current
    if (!area) return
    grow(area)
    // After a history step the caret goes to the end of the recalled text
    if (caretAtEnd.current) {
      caretAtEnd.current = false
      area.setSelectionRange(value.length, value.length)
    }
  }, [value])

  // The same when the panel's width changes and the text wraps differently
  useEffect(() => {
    const area = areaRef.current
    if (!area) return
    const observer = new ResizeObserver(() => grow(area))
    observer.observe(area)
    return () => observer.disconnect()
  }, [])

  // Tell the HUD only when the box goes from empty to not empty and back
  const hasDraft = value.length > 0
  useLayoutEffect(() => {
    if (postedDraft.current === hasDraft) return
    postedDraft.current = hasDraft
    post({ type: 'draft', hasDraft })
    onDraftChange?.(hasDraft)
  }, [hasDraft, onDraftChange])

  /** Show another text in the box and put the caret at its end. */
  function show(text: string) {
    caretAtEnd.current = true
    setValue(text)
  }

  function onKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    const area = event.currentTarget
    // The Enter or Esc of an input method confirms or cancels its conversion: never ours
    if (event.nativeEvent.isComposing || event.keyCode === 229) return

    if (event.key === 'Enter') {
      // Shift+Enter is a line break natively; Option+Enter is made one here
      if (event.shiftKey) return
      event.preventDefault()
      if (event.altKey) {
        insertNewline(area, false)
        return
      }
      // A backslash before the caret turns Enter into a line break, as in the terminal
      if (
        area.selectionStart === area.selectionEnd &&
        area.value.slice(0, area.selectionStart).endsWith('\\')
      ) {
        insertNewline(area, true)
        return
      }
      const text = value.trim()
      // Nothing to send in an empty box
      if (text === '') return
      post({ type: 'submit', text })
      history.current?.push(text)
      setValue('')
      return
    }

    if (event.key === 'Escape') {
      // Esc with text in the box does nothing: the terminal's own rule for it is not documented
      if (value !== '') return
      post({ type: isBusy ? 'interrupt' : 'release' })
      return
    }

    if (
      (event.key === 'ArrowUp' || event.key === 'ArrowDown') &&
      !event.shiftKey &&
      !event.altKey &&
      !event.ctrlKey &&
      !event.metaKey
    ) {
      // In a text of several lines the arrows move the caret; history is for empty and single-line boxes,
      // and for a recalled prompt once the caret is on its first line (Up) or last line (Down)
      const isUp = event.key === 'ArrowUp'
      const isSingleLine = !value.includes('\n')
      const isAtEdge = isUp
        ? !value.slice(0, area.selectionStart).includes('\n')
        : !value.slice(area.selectionEnd).includes('\n')
      if (!isSingleLine && !(history.current?.isWalking && isAtEdge)) return
      const next = isUp ? history.current?.older(value) : history.current?.newer()
      if (next === undefined) return
      event.preventDefault()
      show(next)
    }
  }

  return (
    <div className="input-box">
      <Rule />
      <div className="input-row">
        <span className="input-marker" aria-hidden>
          {'❯ '}
        </span>
        <textarea
          ref={(element) => {
            areaRef.current = element
            registerInput(element)
            return () => registerInput(null)
          }}
          className="input-text"
          aria-label="Prompt"
          rows={1}
          value={value}
          placeholder={placeholder}
          spellCheck={false}
          autoCorrect="off"
          autoCapitalize="off"
          onChange={(event) => {
            // The user typed: the next Up starts from this text
            history.current?.reset()
            setValue(event.target.value)
          }}
          onKeyDown={onKeyDown}
          onFocus={() => post({ type: 'focus', isFocused: true })}
          onBlur={() => post({ type: 'focus', isFocused: false })}
        />
      </div>
      <Rule />
    </div>
  )
}
