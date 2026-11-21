/**
 * The rows of the tools that draw their outcome in words instead of output: the question and plan
 * tools (which have no call row), the worktree tools, and the error and interrupted blocks any tool
 * can end in (`tools.md`, sections 3.8 to 3.10).
 *
 * Why it exists: these are the results that are not a count, a diff or a block of output. Called by
 * {@link ToolRow} and {@link ToolResultView}.
 */
import type { ToolCall } from '@dw/protocol'

import { Markdown } from '../../markdown/Markdown'
import { Dim, Gutter, RowLayout, themeColor, useColumns } from '../../terminal'
import { formatDuration } from '../duration'
import { ClampedText, Strong } from './blocks'
import { field, isRecord, numberField, readList, readText, textField, type ReadText } from './data'
import { displayPath } from './format'
import { InterruptedEdit } from './FileResults'

/** Rows of an error shown before the hint. */
const ERROR_ROWS = 10
/** Columns an error block loses to the result frame. */
const FRAME_COLUMNS = 7

/**
 * The row of a question the model asked: what was answered, or that it was declined.
 *
 * @param props.call - An AskUserQuestion call with its `output` (`questions`, `answers`).
 */
function QuestionRow({ call }: { call: ToolCall }) {
  const answers = isRecord(field(call.output, 'answers'))
    ? Object.entries(field(call.output, 'answers') as object)
    : []
  const questions = readList(field(call.output, 'questions') ?? field(call.input, 'questions')).items
  const timedOut = numberField(call.output, 'afkTimeoutMs')
  if (call.isRunning || (call.output === undefined && !call.isErrored && !call.isInterrupted)) return null
  if (answers.length > 0) {
    return (
      <>
        <RowLayout>Answered Claude&apos;s questions:</RowLayout>
        <Gutter>
          {answers.map(([question, answer]) => (
            <div key={question}>
              <Dim>{`· ${question} → ${typeof answer === 'string' ? answer : JSON.stringify(answer)}`}</Dim>
            </div>
          ))}
        </Gutter>
      </>
    )
  }
  if (timedOut !== undefined && !call.isErrored && !call.isInterrupted) {
    return (
      <RowLayout>{`No response after ${formatDuration(timedOut)} · continued without an answer`}</RowLayout>
    )
  }
  const heading = call.isInterrupted
    ? "Interrupted · no answer saved for Claude's questions:"
    : "Declined to answer Claude's questions:"
  return (
    <>
      <RowLayout>{heading}</RowLayout>
      <Gutter>
        {questions.map((question, index) => {
          const options = readList(field(question, 'options')).items.map(
            (option) => textField(option, 'label') ?? '',
          )
          return (
            <div key={index}>
              <Dim>{`· ${textField(question, 'question') ?? ''} (${options.join(' / ')})`}</Dim>
            </div>
          )
        })}
      </Gutter>
    </>
  )
}

/**
 * The rows of entering or leaving plan mode.
 *
 * @param props.call - An EnterPlanMode or ExitPlanMode call with its `output`.
 */
function PlanRow({ call }: { call: ToolCall }) {
  const color = themeColor('planMode')
  if (call.isRunning || (call.output === undefined && !call.isErrored && !call.isInterrupted)) return null
  if (call.tool === 'EnterPlanMode') {
    if (call.isErrored || call.isInterrupted) return <RowLayout>Declined to enter plan mode</RowLayout>
    return (
      <>
        <RowLayout markerColor={color}>Entered plan mode</RowLayout>
        <Gutter>
          <Dim>Claude is exploring and planning an approach.</Dim>
        </Gutter>
      </>
    )
  }
  if (call.isErrored || call.isInterrupted) return null
  const plan = readText(field(call.output, 'plan'))
  if (!plan || plan.text.trim() === '') return <RowLayout markerColor={color}>Exited plan mode</RowLayout>
  const filePath = textField(call.output, 'filePath')
  return (
    <>
      <RowLayout markerColor={color}>
        <span style={{ color }}>Approved Claude&apos;s plan</span>
      </RowLayout>
      <Gutter>
        <div>
          {filePath !== undefined && <Dim>{`Plan saved to: ${displayPath(filePath)} · /plan to edit`}</Dim>}
          <Markdown source={plan.text} />
        </div>
      </Gutter>
    </>
  )
}

/**
 * The row a call draws when its tool has no call row (the question and plan tools).
 *
 * @param props.call - The call.
 * @returns The result-style rows; null for the tools that draw nothing at all.
 */
export function ResultOnlyRows({ call }: { call: ToolCall }) {
  if (call.tool === 'AskUserQuestion') return <QuestionRow call={call} />
  if (call.tool === 'EnterPlanMode' || call.tool === 'ExitPlanMode') return <PlanRow call={call} />
  return null
}

/**
 * The result of EnterWorktree and ExitWorktree.
 *
 * @param props.call - The call with its `output` (`worktreeBranch`, `worktreePath`, `action`, `originalCwd`).
 */
export function WorktreeResult({ call }: { call: ToolCall }) {
  const branch = textField(call.output, 'worktreeBranch')
  if (call.tool === 'EnterWorktree') {
    const path = textField(call.output, 'worktreePath')
    return (
      <Gutter>
        <div>
          {branch === undefined ? (
            'Switched to worktree'
          ) : (
            <>
              Switched to worktree on branch <Strong>{branch}</Strong>
            </>
          )}
        </div>
        {path !== undefined && (
          <div>
            <Dim>{displayPath(path)}</Dim>
          </div>
        )}
      </Gutter>
    )
  }
  const returned = textField(call.output, 'restoredCwd') ?? textField(call.output, 'originalCwd')
  return (
    <Gutter>
      <div>
        {textField(call.output, 'action') === 'remove' ? (
          'Removed worktree'
        ) : (
          <>
            Kept worktree
            {branch !== undefined && (
              <>
                {' '}
                (branch <Strong>{branch}</Strong>)
              </>
            )}
          </>
        )}
      </div>
      {returned !== undefined && (
        <div>
          <Dim>{`Returned to ${displayPath(returned)}`}</Dim>
        </div>
      )}
    </Gutter>
  )
}

/** Whether an error text is the answer to a permission rule, which keeps its own words. */
function isDenial(text: string): boolean {
  return /doesn't want to proceed|permission|denied|rejected|was blocked/i.test(text)
}

/**
 * The fixed row some tools show in place of a raw error.
 *
 * @param tool - The tool's name.
 * @param text - The raw error text.
 * @returns The wording and whether it is drawn in the error colour; undefined to show the raw error.
 */
function fixedError(tool: string, text: string): { text: string; isError: boolean } | undefined {
  if (isDenial(text) || text.startsWith('InputValidationError')) return undefined
  const missing = /does not exist|no such file|ENOENT|File not found/i.test(text)
  const unread = /has not been read|must be read|read it first/i.test(text)
  switch (tool) {
    case 'Read':
      return { text: missing ? 'File not found' : "Couldn't read file", isError: true }
    case 'Edit':
      if (unread) return { text: 'File must be read first', isError: false }
      return { text: missing ? 'File not found' : "Couldn't edit file", isError: true }
    case 'Write':
      if (unread) return { text: 'File must be read first', isError: false }
      return { text: "Couldn't write file", isError: true }
    case 'Grep':
    case 'Glob':
      return { text: missing ? 'File not found' : "Couldn't search files", isError: true }
    case 'NotebookEdit':
      return { text: "Couldn't edit notebook", isError: true }
    default:
      return undefined
  }
}

/** The raw text of a failed call: its output when that is text, or the text fields of a result object. */
function rawErrorText(output: unknown): ReadText | undefined {
  const direct = readText(output)
  if (direct) return direct
  const parts = ['stdout', 'stderr', 'error', 'message']
    .map((key) => readText(field(output, key)))
    .filter((part): part is ReadText => part !== undefined && part.text.trim() !== '')
  if (parts.length === 0) return undefined
  const text = parts.map((part) => part.text).join('\n')
  return {
    text,
    lines: parts.reduce((sum, part) => sum + part.lines, 0),
    chars: parts.reduce((sum, part) => sum + part.chars, 0),
    isClipped: parts.some((part) => part.isClipped),
  }
}

/**
 * The block of a call that failed: the error in red, ten rows at most.
 *
 * @param props.call - The errored call; its `output` holds the error text or a result object.
 */
export function ErrorResult({ call }: { call: ToolCall }) {
  const columns = useColumns()
  const raw = rawErrorText(call.output)
  const stripped = raw ? raw.text.replaceAll(/<\/?tool_use_error>/g, '').trim() : ''
  const fixed = fixedError(call.tool, stripped)
  if (fixed) {
    return (
      <Gutter>
        <div className={fixed.isError ? 'tool-error' : undefined}>{fixed.text}</div>
      </Gutter>
    )
  }
  let text = stripped
  if (text === '') text = 'Tool execution failed'
  else if (text.startsWith('InputValidationError: ')) text = 'Invalid tool parameters'
  else if (!/^(Error|Cancelled): /.test(text)) text = `Error: ${text}`
  const shown: ReadText = {
    text,
    lines: raw && raw.isClipped ? raw.lines : text.split('\n').length,
    chars: raw && raw.isClipped ? raw.chars : text.length,
    isClipped: raw?.isClipped ?? false,
  }
  return (
    <Gutter>
      <div>
        <ClampedText
          text={shown}
          width={Math.max(columns - FRAME_COLUMNS, 10)}
          limit={ERROR_ROWS}
          className="tool-error"
          hintTone="inactive"
        />
      </div>
    </Gutter>
  )
}

/**
 * The row of a call the user interrupted.
 *
 * @param props.call - The interrupted call.
 */
export function InterruptedResult({ call }: { call: ToolCall }) {
  const path = textField(call.input, 'file_path') ?? textField(call.input, 'notebook_path')
  if (path !== undefined && call.tool === 'Edit') return <InterruptedEdit verb="update" path={path} />
  if (path !== undefined && call.tool === 'Write') return <InterruptedEdit verb="write" path={path} />
  if (path !== undefined && call.tool === 'NotebookEdit') {
    const cell = textField(call.input, 'cell_id')
    return <InterruptedEdit verb="edit" path={path} {...(cell === undefined ? {} : { cell })} />
  }
  return (
    <Gutter>
      <div className="tool-oneline">
        <Dim>Interrupted · What should Claude do instead?</Dim>
      </div>
    </Gutter>
  )
}
