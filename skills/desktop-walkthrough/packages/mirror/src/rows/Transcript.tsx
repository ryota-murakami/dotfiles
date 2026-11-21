import type { Row } from '@dw/protocol'

import { Columns } from '../terminal'
import { RowView } from './RowView'

/**
 * The Transcript: Rows one under the other, in a block that measures its own width in columns.
 *
 * Why it exists: wrapping, tables and lists depend on how wide the page is, so the rows are drawn
 * inside a measuring block. Used by {@link App} for the Session's Rows and by the gallery, which draws
 * the same Rows at two widths.
 *
 * @param props.rows - The Rows, oldest first.
 */
export function Transcript({ rows }: { rows: readonly Row[] }) {
  return (
    <Columns className="transcript">
      {rows.map((row) => (
        <RowView key={row.id} row={row} />
      ))}
    </Columns>
  )
}
