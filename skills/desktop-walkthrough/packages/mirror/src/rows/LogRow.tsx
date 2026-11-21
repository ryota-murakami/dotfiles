import type { LogRow as LogRowData } from '@dw/protocol'

import { GLYPH, RowLayout, themeColor } from '../terminal'

/**
 * A line a plugin wrote into the transcript: `⏺ <plugin>: <text>`, dim from the bullet on.
 *
 * Why it exists: plugins print into the terminal's transcript (a thinking log, a timing, a warning),
 * and the terminal draws each line as a row of its own, named after the plugin. Drawn by
 * {@link RowView} for a `log` Row.
 *
 * @param props.row - The Row.
 */
export function LogRow({ row }: { row: LogRowData }) {
  return (
    <RowLayout marker={GLYPH.bullet} markerColor={themeColor('inactive')} markerLabel="plugin:">
      <span className="dim dim-inactive">{`${row.plugin}: ${row.text}`}</span>
    </RowLayout>
  )
}
