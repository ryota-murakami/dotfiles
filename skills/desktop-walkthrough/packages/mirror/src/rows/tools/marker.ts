/**
 * The marker of a call row: which of its four looks a call has, and the colour and label of each.
 *
 * Why it exists: the call row, the folded line and the agent tree all colour their bullet by the same
 * states (`tools.md`, section 1). Used by {@link ToolRow} and {@link ToolGroupRow}.
 */
import type { ToolCall } from '@dw/protocol'

import { themeColor } from '../../terminal'

/** How a call row's marker is drawn. */
export type MarkerState = 'queued' | 'running' | 'done' | 'errored'

/**
 * Where a call is in its life, as the marker shows it.
 *
 * @param call - The call.
 * @returns `errored` for a failed or interrupted call, `running`, `done` once it has a result, else `queued`.
 */
export function markerState(call: ToolCall): MarkerState {
  if (call.isErrored || call.isInterrupted) return 'errored'
  if (call.isRunning) return 'running'
  return call.output === undefined ? 'queued' : 'done'
}

/** The marker's colour by state: dim while it waits or runs, green when done, red when it failed. */
export const MARKER_COLOR: Record<MarkerState, string> = {
  queued: themeColor('inactive'),
  running: themeColor('inactive'),
  done: themeColor('success'),
  errored: themeColor('error'),
}

/** The marker's screen-reader label by state. */
export const MARKER_LABEL: Record<MarkerState, string> = {
  queued: 'tool queued:',
  running: 'tool running:',
  done: 'tool done:',
  errored: 'tool error:',
}
