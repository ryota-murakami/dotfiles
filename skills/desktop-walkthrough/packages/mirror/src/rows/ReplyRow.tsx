import type { ReplyRow as ReplyRowData } from '@dw/protocol'

import { Markdown } from '../markdown/Markdown'
import { Dim, RowLayout } from '../terminal'

/**
 * One block of the agent's reply: a white bullet, then the markdown.
 *
 * Why it exists: Claude Code draws each text block of a reply as its own row with its own bullet and a
 * blank row above (messages.md, section 4.1), so a reply split by tool calls shows a bullet per block.
 * A block that summarizes the model's thinking ends with the dim tag ` · summary`. Drawn by
 * {@link RowView} for a `reply` Row.
 *
 * @param props.row - The Row. `isFirstOfReply` is not used: the reference has no first-block-only rule.
 */
export function ReplyRow({ row }: { row: ReplyRowData }) {
  // The tag is a space, a middle dot, a no-break space and `summary`
  const tail = row.isSummary ? <Dim>{' · summary'}</Dim> : undefined
  return (
    <RowLayout markerColor="var(--text)" markerLabel="claude:">
      <Markdown source={row.text} tail={tail} />
    </RowLayout>
  )
}
