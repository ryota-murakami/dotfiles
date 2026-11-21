import type { ToolRow as ToolRowData } from '@dw/protocol'

import { Dim, RowLayout } from '../terminal'

/**
 * A tool call with its result. A placeholder until the tool rows are drawn: one dim line naming the tool.
 *
 * Why it exists: the transcript needs something to draw for a `tool` Row, and the work that draws tools
 * the way the terminal does replaces this file's body and nothing else. Drawn by {@link RowView}.
 *
 * @param props.row - The `tool` Row.
 */
export function ToolRow({ row }: { row: ToolRowData }) {
  return (
    <RowLayout>
      <Dim>{`[tool] ${row.tool}${row.isRunning ? ' (running)' : ''}`}</Dim>
    </RowLayout>
  )
}
