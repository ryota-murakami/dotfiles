import type { LiveDocument } from '@dw/protocol'
import { useState } from 'react'

import { Columns } from '../terminal'
import { Footer } from './Footer'
import { InputBox } from './InputBox'
import { SpinnerLine } from './SpinnerLine'
import './live.css'

/**
 * The area under the transcript: the Spinner line while a turn runs, the Input box and the footer.
 *
 * Why it exists: {@link App} reserves the place under the transcript for what changes while a turn
 * runs and for where the user writes. Rendered by {@link App} on every live document. There is no
 * Spinner line without a spinner in the document: the Mirror never invents a word of its own.
 *
 * @param props.live - The newest live document, undefined until the HUD has handed one over.
 * @param props.placeholder - Dim text for the empty Input box, when there is one to show.
 */
export function LiveArea({ live, placeholder }: { live: LiveDocument | undefined; placeholder?: string }) {
  // The footer hides hints that are false for a box with text, so it follows the box's draft
  const [hasDraft, setHasDraft] = useState(false)
  const isBusy = live?.isBusy === true
  return (
    <Columns className="live-area">
      {isBusy && live?.spinner ? <SpinnerLine live={{ ...live, spinner: live.spinner }} /> : null}
      <InputBox
        isBusy={isBusy}
        {...(placeholder === undefined ? {} : { placeholder })}
        onDraftChange={setHasDraft}
      />
      <Footer live={live} hasDraft={hasDraft} />
    </Columns>
  )
}
