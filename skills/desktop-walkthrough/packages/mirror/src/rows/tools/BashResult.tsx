/**
 * What hangs under a Bash (or PowerShell) call: its output, its status rows and the notes the shell
 * adds, drawn as `tools.md` section 3.3 describes.
 *
 * Why it exists: a shell command is the most common call of a Session and has the most parts: standard
 * output, standard error in red, `(No output)`, `Running in the background`, `(timeout 5m)`, `Shell cwd
 * was reset to …`. Called by {@link ToolResultView} for a finished Bash call and for a running one.
 */
import type { ToolCall } from '@dw/protocol'

import { Dim, Gutter, useColumns } from '../../terminal'
import { ClampedText, cleanOutput } from './blocks'
import { field, flagField, readText, textField, type ReadText } from './data'
import { formatTimeout } from './format'
import { callTimeout } from './title'
import { useElapsed } from './useElapsed'

/** Columns the output block loses to the result frame, as the terminal measures it. */
const FRAME_COLUMNS = 10
/** Rows of each stream shown before the hint. */
const OUTPUT_ROWS = 3

/** A shell command reports progress once it has run this long; only then does its timeout note stay. */
const PROGRESS_AFTER_MS = 2000

/** The line the shell tool appends when the shell ended outside the project. */
const CWD_RESET = /(?:^|\n)(Shell cwd was reset to [^\n]+)\s*$/

/**
 * The `Running…` row of a call that has started: with the time the page has seen it run and its timeout.
 *
 * @param props.call - The running call.
 */
export function RunningBash({ call }: { call: ToolCall }) {
  const elapsed = useElapsed(true)
  const timeout = callTimeout(call)
  // The terminal shows the elapsed time once the command has been running a second
  const parts = [
    elapsed !== undefined && elapsed >= 1000 ? formatElapsed(elapsed) : undefined,
    timeout === undefined ? undefined : `timeout ${formatTimeout(timeout)}`,
  ].filter((part): part is string => part !== undefined)
  return (
    <Gutter>
      <Dim>{parts.length > 0 ? `Running… (${parts.join(' · ')})` : 'Running…'}</Dim>
    </Gutter>
  )
}

/** Whole seconds under a minute, then minutes and seconds. */
function formatElapsed(milliseconds: number): string {
  const seconds = Math.floor(milliseconds / 1000)
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`
}

/**
 * The row of a call that was queued: it has not started.
 */
export function WaitingBash() {
  return (
    <Gutter>
      <Dim>Waiting…</Dim>
    </Gutter>
  )
}

/**
 * The result block of a finished Bash call.
 *
 * @param props.call - The call with its `output` (`stdout`, `stderr`, `interrupted`, …).
 */
export function BashResult({ call }: { call: ToolCall }) {
  const columns = useColumns()
  const width = Math.max(columns - FRAME_COLUMNS, 10)
  const output = call.output
  let stdout: ReadText | undefined = readText(field(output, 'stdout'))
  let stderr: ReadText | undefined = readText(field(output, 'stderr'))
  // The shell's own cwd note is a row of its own, under the output: the tool appends it to stderr
  // (to stdout in some builds)
  let cwdNote: string | undefined
  for (const stream of ['stderr', 'stdout'] as const) {
    const text = stream === 'stderr' ? stderr : stdout
    const match = text && !text.isClipped ? CWD_RESET.exec(text.text) : null
    if (!text || !match) continue
    cwdNote = match[1]
    const rest = { ...text, text: text.text.slice(0, match.index) }
    if (stream === 'stderr') stderr = rest
    else stdout = rest
    break
  }
  const hasStdout = stdout !== undefined && cleanOutput(stdout.text) !== ''
  const hasStderr = stderr !== undefined && cleanOutput(stderr.text) !== ''
  const isBackground = textField(output, 'backgroundTaskId') !== undefined
  const interpretation = textField(output, 'returnCodeInterpretation')
  // The note of the timeout stays only under a command that ran long enough to report progress
  const timeout = (call.ranMs ?? 0) >= PROGRESS_AFTER_MS ? callTimeout(call) : undefined
  const status = isBackground
    ? 'Running in the background (↓ to manage)'
    : hasStdout || hasStderr
      ? undefined
      : flagField(output, 'interrupted')
        ? 'Interrupted'
        : (interpretation ?? '(No output)')
  const isImage = flagField(output, 'isImage')
  return (
    <>
      <Gutter>
        <div>
          {isImage ? (
            <Dim>[Image sent to Claude]</Dim>
          ) : (
            hasStdout && stdout && <ClampedText text={stdout} width={width} limit={OUTPUT_ROWS} isLenient />
          )}
          {hasStderr && stderr && (
            <ClampedText text={stderr} width={width} limit={OUTPUT_ROWS} isLenient className="tool-error" />
          )}
          {status !== undefined && !isImage && <Dim>{status}</Dim>}
        </div>
      </Gutter>
      {cwdNote !== undefined && (
        <Gutter>
          <Dim>{cwdNote}</Dim>
        </Gutter>
      )}
      {timeout !== undefined && (
        <Gutter>
          <Dim>{`(timeout ${formatTimeout(timeout)})`}</Dim>
        </Gutter>
      )}
    </>
  )
}
