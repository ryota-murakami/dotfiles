import type { NoticeRow as NoticeRowData } from '@dw/protocol'

import { Dim, RowLayout } from '../terminal'

/**
 * A dim note: the model's source, a settings hint, with ` · /command` after it when it has one.
 *
 * Why it exists: the terminal prints these as `InfoNotice`s under its logo, two columns in, dim.
 * Drawn by {@link RowView} for a `notice` Row.
 *
 * @param props.row - The Row.
 */
export function NoticeRow({ row }: { row: NoticeRowData }) {
  return (
    <RowLayout marker={false} className="notice">
      <Dim>{row.command === null ? row.text : `${row.text} · ${row.command}`}</Dim>
    </RowLayout>
  )
}
