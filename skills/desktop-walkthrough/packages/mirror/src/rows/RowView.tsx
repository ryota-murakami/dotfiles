import type { Row } from '@dw/protocol'
import { memo } from 'react'

import { CommandOutputRow } from './CommandOutputRow'
import { LogRow } from './LogRow'
import { NoticeRow } from './NoticeRow'
import { PromptRow } from './PromptRow'
import { ReplyRow } from './ReplyRow'
import { ToolGroupRow } from './ToolGroupRow'
import { ToolRow } from './ToolRow'
import { TurnDurationRow } from './TurnDurationRow'

/**
 * Draw one Row of the Transcript with the component of its kind.
 *
 * Why it exists: a Transcript is a list of Rows of eight kinds, and each kind is drawn by its own
 * component in its own file; this is the one place that maps a kind to its component. Called by
 * {@link Transcript} for every Row.
 *
 * It draws again only when its Row is another object: the store keeps a Row that did not change as it was.
 *
 * @param props.row - The Row from the protocol.
 */
export const RowView = memo(function RowView({ row }: { row: Row }) {
  switch (row.kind) {
    case 'prompt':
      return <PromptRow row={row} />
    case 'reply':
      return <ReplyRow row={row} />
    case 'tool':
      return <ToolRow row={row} />
    case 'tool-group':
      return <ToolGroupRow row={row} />
    case 'command-output':
      return <CommandOutputRow row={row} />
    case 'turn-duration':
      return <TurnDurationRow row={row} />
    case 'notice':
      return <NoticeRow row={row} />
    case 'log':
      return <LogRow row={row} />
  }
})
