import type { ToolGroupRow as ToolGroupRowData } from '@dw/protocol'

import { Dim, GLYPH, Gutter, RowLayout, themeColor } from '../terminal'
import { formatDuration } from './duration'
import { AgentGroup } from './tools/AgentGroup'
import { Strong } from './tools/blocks'
import { latestDetail, summarizeGroup, type GroupClause } from './tools/group'
import { isRowlessTool } from './tools/title'
import { useElapsed } from './tools/useElapsed'
import './tools/tools.css'

/** The elapsed time shows on a live line once it passes this many milliseconds. */
const ELAPSED_AFTER_MS = 2000

/** One clause of the line, its counts bold. */
function Clause({ clause, isFirst }: { clause: GroupClause; isFirst: boolean }) {
  return (
    <>
      {clause.map((part, index) => {
        // The line starts with a capital letter
        const text =
          isFirst && index === 0 ? part.text.charAt(0).toUpperCase() + part.text.slice(1) : part.text
        return part.isBold ? <Strong key={index}>{text}</Strong> : text
      })}
    </>
  )
}

/**
 * A run of tool calls the terminal folds into one line.
 *
 * Why it exists: consecutive read, search and shell calls would fill the Transcript, so the terminal
 * folds them into `Searched for 3 patterns, read 2 files` (`Searching for 3 patterns, reading 2
 * files… · 5s` while they run, with the latest file or pattern under it), after `Thought for 8s` when
 * the model thought inside the run. A finished run is dim with a
 * blank marker; a run with a failed call has a red marker and ends with ` N failed`. A run of agents is
 * drawn as the agent tree instead. Drawn by {@link RowView} for a `tool-group` Row.
 *
 * @param props.row - The `tool-group` Row.
 */
export function ToolGroupRow({ row }: { row: ToolGroupRowData }) {
  // The elapsed time counts a call that runs, not a live run whose calls are done
  const elapsed = useElapsed(row.isActive && row.calls.some((call) => call.isRunning))
  const visible = row.calls.filter((call) => !isRowlessTool(call.tool))
  // A group of agent calls has its own layout
  if (visible.length > 1 && visible.every((call) => call.tool === 'Agent' || call.tool === 'Task')) {
    return <AgentGroup calls={visible} isActive={row.isActive} />
  }
  const { clauses, failed } = summarizeGroup(row.calls, row.isActive, row.thoughtMs)
  // Only calls that draw no row, and no thinking: the group draws nothing either
  if (clauses.length === 0) return null
  const detail = row.isActive ? latestDetail(row.calls) : undefined
  const hasElapsed = elapsed !== undefined && elapsed >= ELAPSED_AFTER_MS
  const line = (
    <>
      {clauses.map((clause, index) => (
        <span key={index}>
          {index > 0 && ', '}
          <Clause clause={clause} isFirst={index === 0} />
        </span>
      ))}
      {failed > 0 && <span className="tool-error"> {failed} failed</span>}
      {hasElapsed && <Dim>{` · ${formatDuration(elapsed)}`}</Dim>}
      {row.isActive && '…'}
      <Dim>{' (ctrl+o to expand)'}</Dim>
    </>
  )
  return (
    <div className="tool-call">
      <RowLayout
        marker={row.isActive || failed > 0 ? GLYPH.bullet : ' '}
        markerColor={failed > 0 ? themeColor('error') : themeColor('inactive')}
        markerLabel={row.isActive ? 'tool running:' : 'tool:'}
        className={row.isActive ? 'tool-running' : ''}
      >
        {/* A finished run is dim as a whole */}
        {row.isActive ? line : <span className="dim dim-inactive">{line}</span>}
      </RowLayout>
      {detail !== undefined && (
        <Gutter>
          <Dim>{detail}</Dim>
        </Gutter>
      )}
    </div>
  )
}
