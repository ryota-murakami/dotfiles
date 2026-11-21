import type { TurnDurationRow as TurnDurationRowData } from '@dw/protocol'

import { Dim, GLYPH, RowLayout } from '../terminal'
import { formatClockTime, formatDuration } from './duration'

/**
 * The line that closes a turn: `✻ Baked for 3s`, dim, with a blank row above.
 *
 * Why it exists: the terminal appends it when a turn finishes, and the Mirror shows the same close.
 * Drawn by {@link RowView} for a `turn-duration` Row.
 *
 * @param props.row - The Row; `finishedAt`, when the Bridge knew it, adds ` · done 3:04 PM`, and
 *   `stillRunning` adds ` · 3 shells still running`.
 */
export function TurnDurationRow({ row }: { row: TurnDurationRowData }) {
  const done = row.finishedAt === undefined ? '' : ` · done ${formatClockTime(row.finishedAt)}`
  const stillRunning = row.stillRunning === undefined ? '' : ` · ${row.stillRunning} still running`
  return (
    <RowLayout marker={GLYPH.notice} markerColor="var(--inactive)">
      <Dim>{`${row.word} for ${formatDuration(row.durationMs)}${done}${stillRunning}`}</Dim>
    </RowLayout>
  )
}
