import type { Row } from '@dw/protocol'
import { act, render } from '@testing-library/react'
import { afterEach, beforeEach, expect, test, vi } from 'vitest'

import { RowView } from '../RowView'
import { diffWords } from './wordDiff'

/** Draw one Row; its text has the gutter's no-break space as a plain space. */
function draw(row: Row) {
  const container = render(<RowView row={row} />).container
  return { container, text: (container.textContent ?? '').replaceAll('\u00a0', ' ') }
}

/** A finished tool Row. */
function tool(id: string, name: string, input: unknown, output?: unknown, flags: object = {}): Row {
  return {
    kind: 'tool',
    id,
    tool: name,
    input,
    isRunning: false,
    isErrored: false,
    isInterrupted: false,
    ...(output === undefined ? {} : { output }),
    ...flags,
  }
}

/** A call of a folded run: a tool Row without its Row fields. */
const call = (name: string, input: object, output: object) => {
  const { kind: _kind, id: _id, ...rest } = tool('x', name, input, output) as Extract<Row, { kind: 'tool' }>
  return rest
}

beforeEach(() => {
  vi.useFakeTimers()
})
afterEach(() => {
  vi.useRealTimers()
})

test('shows a finished Bash call with a green bullet, its command and its output under the gutter', () => {
  // Arrange
  const row = tool(
    't',
    'Bash',
    { command: 'git status --short' },
    { stdout: ' M a.ts', stderr: '', interrupted: false },
  )

  // Act
  const { container, text } = draw(row)

  // Assert
  expect(text).toBe('⏺Bash(git status --short)  ⎿   M a.ts')
  expect(container.querySelector<HTMLElement>('.marker')?.style.color).toBe('var(--success)')
})

test('cuts long Bash output to three rows and ends it with the expand hint', () => {
  // Arrange
  const head = 'one\ntwo\nthree\nfour\nfive'
  const row = tool(
    't',
    'Bash',
    { command: 'seq 50' },
    { stdout: { head, lines: 50, chars: 190 }, stderr: '' },
  )

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe('⏺Bash(seq 50)  ⎿  onetwothree… +47 lines (ctrl+o to expand)')
})

test('shows a queued Bash call as waiting and a running one with its timeout', () => {
  // Arrange
  const queued = tool('q', 'Bash', { command: 'a' })
  const running = tool('r', 'Bash', { command: 'b', timeout: 120_000 }, undefined, { isRunning: true })

  // Act
  const queuedText = draw(queued).text
  const drawn = draw(running)

  // Assert
  expect(queuedText).toBe('⏺Bash(a)  ⎿  Waiting…')
  expect(drawn.text).toBe('⏺Bash(b)  ⎿  Running… (timeout 2m)')
  expect(drawn.container.querySelector('.tool-running')).not.toBeNull()
})

test('counts the seconds the page has seen a Bash call run', () => {
  // Arrange
  const row = tool('r', 'Bash', { command: 'b' }, undefined, { isRunning: true })
  const { container } = draw(row)

  // Act
  act(() => {
    vi.advanceTimersByTime(5000)
  })

  // Assert
  expect(container.textContent).toContain('Running… (5s)')
})

test('shows an errored call with a red bullet and the error text prefixed', () => {
  // Arrange
  const row = tool('t', 'Bash', { command: 'false' }, 'Exit code 1\nboom', { isErrored: true })

  // Act
  const { container, text } = draw(row)

  // Assert
  expect(text).toBe('⏺Bash(false)  ⎿  Error: Exit code 1boom')
  expect(container.querySelector<HTMLElement>('.marker')?.style.color).toBe('var(--error)')
})

test('shows Read as the number of lines and Grep as the number of files found', () => {
  // Arrange
  const read = tool('r', 'Read', { file_path: '/tmp/a.ts' }, { type: 'text', file: { numLines: 120 } })
  const grep = tool('g', 'Grep', { pattern: 'foo', path: 'src' }, { mode: 'files_with_matches', numFiles: 1 })

  // Act
  const readText = draw(read).text
  const grepText = draw(grep).text

  // Assert
  expect(readText).toBe('⏺Read(/tmp/a.ts)  ⎿  Read 120 lines')
  expect(grepText).toBe('⏺Search(pattern: "foo", path: "src")  ⎿  Found 1 file (ctrl+o to expand)')
})

test('shows an Edit as added and removed line counts with numbered diff rows', () => {
  // Arrange
  const patch = [
    { oldStart: 4, oldLines: 2, newStart: 4, newLines: 2, lines: [' keep', '-const a = 1', '+const a = 2'] },
  ]
  const row = tool(
    'e',
    'Edit',
    { file_path: '/tmp/a.ts', old_string: 'x', new_string: 'y' },
    { structuredPatch: patch },
  )

  // Act
  const { container, text } = draw(row)

  // Assert
  expect(text).toBe('⏺Update(/tmp/a.ts)  ⎿  Added 1 line, removed 1 line4  keep5 -const a = 15 +const a = 2')
  expect(container.querySelectorAll('.diff-add').length).toBe(1)
  expect(container.querySelectorAll('.diff-remove').length).toBe(1)
})

test('highlights only the changed word between a removed and an added line', () => {
  // Arrange
  const removed = 'return total + 1'
  const added = 'return total + 2'

  // Act
  const words = diffWords(removed, added)

  // Assert
  expect(words?.added.filter((span) => span.isChanged).map((span) => span.text)).toEqual(['2'])
  expect(words?.removed.filter((span) => span.isChanged).map((span) => span.text)).toEqual(['1'])
})

test('leaves word highlights off when most of the line changed', () => {
  // Arrange / Act
  const words = diffWords('alpha beta gamma', 'one two three four')

  // Assert
  expect(words).toBeUndefined()
})

test('shows a new file as wrote N lines with a ten-row preview and the hidden count', () => {
  // Arrange
  const content = {
    head: Array.from({ length: 30 }, (_, i) => `line ${i + 1}`).join('\n'),
    lines: 95,
    chars: 4000,
  }
  const row = tool(
    'w',
    'Write',
    { file_path: '/tmp/x.txt', content },
    { type: 'create', filePath: '/tmp/x.txt', content },
  )

  // Act
  const { container, text } = draw(row)

  // Assert
  expect(text).toContain('Wrote 95 lines to /tmp/x.txt')
  expect(container.querySelectorAll('.code-row').length).toBe(10)
  expect(text).toContain('… +85 lines (~4 KB) (ctrl+o to expand)')
})

test('draws nothing for the todo, tool search and task tools', () => {
  // Arrange
  const rows = ['TodoWrite', 'ToolSearch', 'TaskCreate'].map((name) => tool(name, name, {}, {}))

  // Act
  const texts = rows.map((row) => draw(row).text)

  // Assert
  expect(texts).toEqual(['', '', ''])
})

test('shows an answered question as a bullet row with one dim line per answer', () => {
  // Arrange
  const row = tool(
    'a',
    'AskUserQuestion',
    { questions: [] },
    { questions: [], answers: { 'Which format?': 'YAML' } },
  )

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe("⏺Answered Claude's questions:  ⎿  · Which format? → YAML")
})

test('names an MCP call after its server and tool and lists its arguments', () => {
  // Arrange
  const row = tool('m', 'mcp__docs__search_pages', { query: 'limits', limit: 5 }, 'Page one')

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe('⏺docs - search_pages (MCP)(query: "limits", limit: 5)  ⎿  Page one')
})

test('shows a tool the terminal has no name for as its name with its arguments', () => {
  // Arrange
  const row = tool('u', 'FrobnicateTool', { target: 'alpha' }, undefined)

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe('⏺FrobnicateTool(target: "alpha")')
})

test('folds finished searches and reads into one dim line', () => {
  // Arrange
  const row: Row = {
    kind: 'tool-group',
    id: 'g',
    isActive: false,
    calls: [
      call('Grep', { pattern: 'a' }, { numFiles: 1 }),
      call('Grep', { pattern: 'b' }, { numFiles: 1 }),
      call('Read', { file_path: '/p/a.ts' }, { type: 'text', file: { numLines: 1 } }),
      call('Read', { file_path: '/p/b.ts' }, { type: 'text', file: { numLines: 1 } }),
    ],
  }

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe(' Searched for 2 patterns, read 2 files (ctrl+o to expand)')
})

test('words a live folded run in the progressive form with the latest file under it', () => {
  // Arrange
  const row: Row = {
    kind: 'tool-group',
    id: 'g',
    isActive: true,
    calls: [
      {
        tool: 'Read',
        input: { file_path: '/p/a.ts' },
        isRunning: true,
        isErrored: false,
        isInterrupted: false,
      },
    ],
  }

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe('⏺Reading 1 file… (ctrl+o to expand)  ⎿  /p/a.ts')
})

test('starts a finished folded run with how long the model thought inside it', () => {
  // Arrange
  const row: Row = {
    kind: 'tool-group',
    id: 'g-thought',
    isActive: false,
    thoughtMs: 19_400,
    calls: [
      call('Bash', { command: 'ls src' }, { stdout: 'a.ts', stderr: '', interrupted: false }),
      call('Bash', { command: 'ls docs' }, { stdout: 'b.md', stderr: '', interrupted: false }),
    ],
  }

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe(' Thought for 19s, listed 2 directories (ctrl+o to expand)')
})

test('shows a run that only held thinking as the time the model thought', () => {
  // Arrange
  const row: Row = { kind: 'tool-group', id: 'g-only-thought', isActive: false, thoughtMs: 8200, calls: [] }

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe(' Thought for 8s (ctrl+o to expand)')
})

test("hangs the shell's cwd note under the output as a dim row of its own", () => {
  // Arrange
  const row = tool(
    'bash-cwd',
    'Bash',
    { command: 'cd /tmp && ls' },
    { stdout: 'a.txt', stderr: '\nShell cwd was reset to /home/user/project', interrupted: false },
  )

  // Act
  const { container, text } = draw(row)

  // Assert
  expect(text).toBe('⏺Bash(cd /tmp && ls)  ⎿  a.txt  ⎿  Shell cwd was reset to /home/user/project')
  expect(container.querySelector('.tool-error')).toBeNull()
})

test('keeps the timeout note only under a command that ran for seconds', () => {
  // Arrange
  const quick = tool(
    'bash-quick',
    'Bash',
    { command: 'pnpm test', timeout: 300_000 },
    { stdout: 'ok', stderr: '' },
  )
  const slow = tool(
    'bash-slow',
    'Bash',
    { command: 'pnpm build', timeout: 300_000 },
    { stdout: 'ok', stderr: '' },
    {
      ranMs: 41_000,
    },
  )

  // Act
  const quickText = draw(quick).text
  const slowText = draw(slow).text

  // Assert
  expect(quickText).toBe('⏺Bash(pnpm test)  ⎿  ok')
  expect(slowText).toBe('⏺Bash(pnpm build)  ⎿  ok  ⎿  (timeout 5m)')
})

test('cuts a long line of command output where the row ends and counts the rows that leaves out', () => {
  // Arrange: 80 columns leave 70 for output; one line of 300 characters makes five rows
  const row = tool('bash-long', 'Bash', { command: 'cat min.js' }, { stdout: 'ab '.repeat(100), stderr: '' })

  // Act
  const { container } = draw(row)

  // Assert
  const rows = [...container.querySelectorAll('.tool-row')].map((element) => element.textContent)
  expect(rows).toEqual([
    'ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab a',
    'b ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab',
    ' ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab',
  ])
  expect(container.textContent).toContain('… +2 lines (ctrl+o to expand)')
})

test('draws nothing for a call whose input has not arrived yet', () => {
  // Arrange
  const row = tool('bash-arriving', 'Bash', {})

  // Act
  const { text } = draw(row)

  // Assert
  expect(text).toBe('')
})
