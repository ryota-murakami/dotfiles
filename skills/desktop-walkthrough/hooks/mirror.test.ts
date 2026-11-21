import { expect, test } from 'claude-code/testing'
import {
  captureGroup,
  captureReply,
  captureTool,
  chunkChars,
  clipText,
  clipValue,
  currentRows,
  newPlacement,
  noteThought,
  place,
  resetMirror,
} from './mirror'

// A fake credential assembled at run time, so secret scanners do not flag this public file
const TOKEN = 'a1b2c3d4'.repeat(4)

test('a short command output reaches the Mirror whole', () => {
  // Arrange
  const output = 'On branch main\nnothing to commit'

  // Act
  const carried = clipText(output)

  // Assert
  expect(carried).toBe('On branch main\nnothing to commit')
})

test('a long command output reaches the Mirror as its first lines and the size of the whole', () => {
  // Arrange
  const output = 'line 1\nline 2\nline 3\nline 4\nline 5'

  // Act
  const carried = clipText(output, 2, 1000)

  // Assert
  expect(carried).toEqual({ head: 'line 1\nline 2', lines: 5, chars: 34 })
})

test('a secret in a tool result is hidden before it reaches the Mirror', () => {
  // Arrange
  const result = { stdout: `curl -H 'Authorization: Bearer ${TOKEN}' https://api.test/me`, interrupted: false }

  // Act
  const carried = clipValue(result)

  // Assert
  expect(carried).toEqual({ stdout: "curl -H 'Authorization: Bearer •••' https://api.test/me", interrupted: false })
})

test('a long list in a tool result is cut and says how many items were left out', () => {
  // Arrange
  const lines = Array.from({ length: 203 }, (_, index) => `+${index}`)

  // Act
  const carried = clipValue({ lines }) as { lines: unknown[] }

  // Assert
  expect(carried.lines.length).toBe(201)
  expect(carried.lines[200]).toEqual({ __dwMore: 3 })
})

test('a new row goes under the rows already shown', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'prompt', 1000)
  place(placement, 'reply', 5000)

  // Act
  place(placement, 'tool', 9000)

  // Assert
  expect(placement.order).toEqual(['prompt', 'reply', 'tool'])
})

test('a row first seen in a redraw takes the place the redraw shows, between rows already known', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'a', 1000)
  place(placement, 'c', 5000)
  place(placement, 'd', 9000)

  // Act: the terminal redraws its rows top to bottom within a few milliseconds
  place(placement, 'a', 20000)
  place(placement, 'c', 20001)
  place(placement, 'x', 20002)
  place(placement, 'd', 20003)

  // Assert
  expect(placement.order).toEqual(['a', 'c', 'x', 'd'])
})

test('rows first seen at the top of a redraw go above the rows already known', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'c', 1000)
  place(placement, 'd', 5000)

  // Act
  place(placement, 'a', 20000)
  place(placement, 'b', 20001)
  place(placement, 'c', 20002)
  place(placement, 'd', 20003)

  // Assert
  expect(placement.order).toEqual(['a', 'b', 'c', 'd'])
})

test('a row that follows the redraw of one earlier row still goes last', () => {
  // Arrange
  const placement = newPlacement()
  place(placement, 'a', 1000)
  place(placement, 'b', 5000)
  place(placement, 'c', 9000)

  // Act: an earlier row changes, and a new row is drawn right after it
  place(placement, 'a', 20000)
  place(placement, 'new', 20002)

  // Assert
  expect(placement.order).toEqual(['a', 'b', 'c', 'new'])
})

test('the spinner line counts streamed text, thinking and tool arguments, and nothing for the engine\'s own items', () => {
  // Arrange
  const chunks = [
    { kind: 'text', index: 0, text: 'done' },
    { kind: 'thinking', index: 1, text: 'hmm' },
    { kind: 'input', index: 2, json: '{"a":1}' },
    { kind: 'tool', index: 2, id: 'toolu_1', name: 'Bash' },
    { kind: 'engine', ref: 7 },
  ] as const

  // Act
  const chars = chunks.map(chunk => chunkChars(chunk))

  // Assert
  expect(chars).toEqual([4, 3, 7, 0, 0])
})

/** A tool call as the terminal hands it to its own row. */
const call = (id: string, tool: string, input: unknown) => ({
  tool_use_id: id,
  tool,
  input,
  isRunning: false,
  isErrored: false,
  isInterrupted: false,
})

/** A folded run as the terminal hands it to its line. */
const run = (calls: ReturnType<typeof call>[], isActive: boolean) => ({ calls, isActive, isExpanded: false, isCallsOnly: true })

test('a call drawn on its own while its input arrives is shown once after it joins a folded run', () => {
  // Arrange
  resetMirror()
  captureTool('call-1', { ...call('call-1', 'Bash', {}), isExpanded: false })
  captureTool('call-2', { ...call('call-2', 'Bash', { command: 'pnpm test' }), isExpanded: false })

  // Act
  captureGroup('run-1', run([call('call-1', 'Bash', { command: 'ls src' })], true))

  // Assert
  expect(currentRows().map(row => `${row.kind} ${row.id}`)).toEqual(['tool-group run-1', 'tool call-2'])
})

test('a folded run drawn again under a new id is shown once, where it stood', () => {
  // Arrange
  resetMirror()
  captureGroup('run-while-streaming', run([call('call-1', 'Read', { file_path: 'a.ts' })], true))
  captureTool('call-2', { ...call('call-2', 'Bash', { command: 'pnpm test' }), isExpanded: false })

  // Act
  captureGroup('run-once-whole', run([call('call-1', 'Read', { file_path: 'a.ts' })], true))

  // Assert
  expect(currentRows().map(row => `${row.kind} ${row.id}`)).toEqual(['tool-group run-once-whole', 'tool call-2'])
})

test('a folded run says how long the model thought inside it', () => {
  // Arrange
  resetMirror()
  captureGroup('run-1', run([call('call-1', 'Read', { file_path: 'a.ts' })], true))

  // Act
  noteThought(8200, Date.now())
  noteThought(11000, Date.now())

  // Assert
  expect(currentRows()).toEqual([
    {
      kind: 'tool-group',
      id: 'run-1',
      calls: [{ tool: 'Read', input: { file_path: 'a.ts' }, isRunning: false, isErrored: false, isInterrupted: false }],
      isActive: true,
      thoughtMs: 19200,
    },
  ])
})

test('thinking that ends before the terminal draws its run is given to that run', () => {
  // Arrange
  resetMirror()
  noteThought(8200, Date.now())

  // Act
  captureGroup('run-1', run([], false))

  // Assert
  expect(currentRows()).toEqual([{ kind: 'tool-group', id: 'run-1', calls: [], isActive: false, thoughtMs: 8200 }])
})

test('a run that holds no call and no thinking shows nothing', () => {
  // Arrange
  resetMirror()

  // Act
  captureGroup('run-1', run([], false))

  // Assert
  expect(currentRows()).toEqual([])
})

test('a run that goes on under a new id keeps the thinking it held', () => {
  // Arrange
  resetMirror()
  noteThought(8200, Date.now())
  captureGroup('run-while-streaming', run([], true))

  // Act
  captureGroup('run-once-whole', run([call('call-1', 'Read', { file_path: 'a.ts' })], true))

  // Assert
  expect(currentRows().map(row => (row.kind === 'tool-group' ? `${row.id} ${row.thoughtMs}` : row.kind))).toEqual([
    'run-once-whole 8200',
  ])
})

test('a folded call that the ctrl+o view draws in full stays folded', () => {
  // Arrange
  resetMirror()
  captureGroup('run-1', run([call('call-1', 'Read', { file_path: 'a.ts' })], false))

  // Act
  captureTool('call-1', { ...call('call-1', 'Read', { file_path: 'a.ts' }), isExpanded: true })

  // Assert
  expect(currentRows().map(row => `${row.kind} ${row.id}`)).toEqual(['tool-group run-1'])
})

test('a call that ran says how long the terminal showed it running', () => {
  // Arrange
  resetMirror()
  captureTool('call-1', { ...call('call-1', 'Bash', { command: 'pnpm build' }), isRunning: true, isExpanded: false }, 10_000)

  // Act
  captureTool('call-1', { ...call('call-1', 'Bash', { command: 'pnpm build' }), isExpanded: false, output: { stdout: 'ok' } }, 51_000)

  // Assert
  expect(currentRows()).toEqual([
    {
      kind: 'tool',
      id: 'call-1',
      tool: 'Bash',
      input: { command: 'pnpm build' },
      isRunning: false,
      isErrored: false,
      isInterrupted: false,
      output: { stdout: 'ok' },
      ranMs: 41_000,
    },
  ])
})

test('a reply the terminal draws again under its own id after a compaction is shown once', () => {
  // Arrange
  resetMirror()
  captureReply('2f84b0e2-79df-4460-9d7e-000000000000', { text: 'Tests pass.', isFirstOfReply: true })
  captureTool('call-1', { ...call('call-1', 'Bash', { command: 'pnpm test' }), isExpanded: false })

  // Act
  captureReply('2f84b0e2-79df-4460-9d7e-bf56f6a1f31b', { text: 'Tests pass.', isFirstOfReply: true })

  // Assert
  expect(currentRows().map(row => `${row.kind} ${row.id}`)).toEqual([
    'reply 2f84b0e2-79df-4460-9d7e-000000000000',
    'tool call-1',
  ])
})

test('two blocks of one reply stay two rows', () => {
  // Arrange
  resetMirror()
  captureReply('2f84b0e2-79df-4460-9d7e-000000000000', { text: 'First the plan.', isFirstOfReply: true })

  // Act
  captureReply('2f84b0e2-79df-4460-9d7e-000000000001', { text: 'Then the result.', isFirstOfReply: false })

  // Assert
  expect(currentRows().map(row => (row.kind === 'reply' ? row.text : row.kind))).toEqual(['First the plan.', 'Then the result.'])
})
