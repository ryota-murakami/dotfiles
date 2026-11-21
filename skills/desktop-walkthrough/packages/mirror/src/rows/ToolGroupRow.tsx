import type { ToolGroupRow as ToolGroupRowData } from '@dw/protocol'

import { Dim, RowLayout } from '../terminal'

/**
 * A run of tool calls the terminal folds into one line. A placeholder until those rows are drawn: one dim
 * line with the number of calls.
 *
 * Why it exists: the transcript needs something to draw for a `tool-group` Row, and the work that draws
 * groups the way the terminal does replaces this file's body and nothing else. Drawn by {@link RowView}.
 *
 * @param props.row - The `tool-group` Row.
 */
export function ToolGroupRow({ row }: { row: ToolGroupRowData }) {
  return (
    <RowLayout>
      <Dim>{`[tool group] ${row.calls.length} calls`}</Dim>
    </RowLayout>
  )
}
