import type { LiveDocument } from '@dw/protocol'

import { Dim } from '../terminal'

/**
 * The area under the transcript: the spinner line, the Input box and the footer. A placeholder until
 * they are drawn: one dim line saying whether the Session is busy.
 *
 * Why it exists: {@link App} reserves the place under the transcript for what changes while a turn
 * runs, and the work that draws the spinner line, the Input box and the footer replaces this file's
 * body and nothing else. Rendered by {@link App} on every live document.
 *
 * @param props.live - The newest live document, undefined until the HUD has handed one over.
 */
export function LiveArea({ live }: { live: LiveDocument | undefined }) {
  return (
    <div className="live-area">
      <Dim>{live === undefined ? '[live area]' : `[live area] ${live.isBusy ? 'busy' : 'idle'}`}</Dim>
    </div>
  )
}
