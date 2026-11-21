import type { ToolRow as ToolRowData } from '@dw/protocol'

import { Dim, RowLayout } from '../terminal'
import { MARKER_COLOR, MARKER_LABEL, markerState } from './tools/marker'
import { ResultOnlyRows } from './tools/StatusRows'
import { describeCall } from './tools/title'
import { ToolResultView } from './tools/ToolResultView'
import './tools/tools.css'

/**
 * Whether a call is still being written by the model: it has no input yet and has not started.
 *
 * @param row - The `tool` Row.
 * @returns True while the row carries an empty input and nothing about a run or a result.
 */
function isAwaitingInput(row: ToolRowData): boolean {
  const { input } = row
  const isEmpty =
    typeof input === 'object' && input !== null && !Array.isArray(input) && Object.keys(input).length === 0
  return isEmpty && !row.isRunning && !row.isErrored && !row.isInterrupted && row.output === undefined
}

/**
 * A tool call as the terminal draws it: the marker, the bold name with its argument summary, and the
 * result block under it.
 *
 * Why it exists: a call is the unit of a coding Session's work, and `tools.md` says how each tool's
 * title and result read. The marker is dim while the call waits, dim and blinking (visible 600 ms,
 * blank 600 ms) while it runs, green when it is done, red when it failed or was interrupted. Tools whose
 * call has no row (todo and task tools, the question and plan tools) draw only their result-style rows,
 * or nothing, and a call whose input is still arriving draws nothing. Drawn by {@link RowView} for a
 * `tool` Row.
 *
 * @param props.row - The `tool` Row.
 */
export function ToolRow({ row }: { row: ToolRowData }) {
  // A call whose input has not arrived has nothing to title: the terminal draws no row for it yet
  if (isAwaitingInput(row)) return null
  const title = describeCall(row)
  if (title === null) return <ResultOnlyRows call={row} />
  const state = markerState(row)
  const hasSummary = title.summary !== ''
  return (
    <div className="tool-call">
      <RowLayout
        markerColor={MARKER_COLOR[state]}
        markerLabel={MARKER_LABEL[state]}
        className={state === 'running' ? 'tool-running' : ''}
      >
        <div className="tool-title">
          <span className="tool-name">{title.name}</span>
          {/* The summary wraps in its own box, so its continuation lines start under the parenthesis */}
          {(hasSummary || title.tag !== undefined) && (
            <span className="tool-summary">
              {hasSummary && `(${title.summary})`}
              {title.tag !== undefined && <Dim>{`${hasSummary ? ' ' : ''}${title.tag}`}</Dim>}
            </span>
          )}
        </div>
      </RowLayout>
      <ToolResultView call={row} />
    </div>
  )
}
