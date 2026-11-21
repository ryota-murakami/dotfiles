import { LiveArea } from './live/LiveArea'
import { Transcript } from './rows/Transcript'
import { useLive, useTranscript } from './store'
import { useStickToBottom } from './terminal'

/**
 * The Mirror: the Session's Transcript, drawn row by row, scrolling to follow new Rows, with the live
 * area under it.
 *
 * Why it exists: it is the page's root; `main.tsx` renders it and the HUD's documents reach it through
 * the store.
 */
export function App() {
  const transcript = useTranscript()
  const live = useLive()
  const scrollRef = useStickToBottom()

  return (
    <div className="mirror">
      <div ref={scrollRef} className="mirror-scroll">
        {/* The first child is what grows; the scroll hook watches it */}
        {transcript ? (
          <Transcript rows={transcript.rows} />
        ) : (
          <p className="mirror-empty dim dim-inactive">Waiting for the session…</p>
        )}
      </div>
      <LiveArea live={live} />
    </div>
  )
}
