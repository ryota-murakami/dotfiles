import type { CommandOutputRow as CommandOutputRowData } from '@dw/protocol'

import { Markdown } from '../markdown/Markdown'
import { Gutter } from '../terminal'

/** The sentinel Claude Code prints for a command that printed nothing. */
const NO_CONTENT = '(no content)'

/**
 * What a slash command printed, under its echo, inside the `⎿` gutter.
 *
 * Why it exists: the echo (`❯ /name args`) is an ordinary Prompt row; the output arrives as its own
 * Row and the terminal hangs it under the echo with no blank row between. Standard output is markdown;
 * an errored command's text is drawn in the `error` colour, wrapped. Drawn by {@link RowView}.
 *
 * @param props.row - The Row. Its `command` and `args` are not drawn: the echo already shows them.
 */
export function CommandOutputRow({ row }: { row: CommandOutputRowData }) {
  const text = row.text.trim()
  // Empty output and the "(no content)" sentinel draw nothing
  if (text === '' || text === NO_CONTENT) return null
  return (
    <Gutter>{row.isErrored ? <div className="reply-error">{text}</div> : <Markdown source={text} />}</Gutter>
  )
}
