import { mirrorDocumentSchema, type MirrorDocument } from '@dw/protocol'
import { useSyncExternalStore } from 'react'

/** The newest document the HUD handed over, and who waits for the next one. */
let current: MirrorDocument | undefined
const listeners = new Set<() => void>()

/**
 * Take a document from the HUD.
 *
 * Why it exists: the page runs in a web view that may not read files, so the HUD reads what the
 * Bridge wrote and calls this with it. Called by the HUD through `window.dwMirror.receive`, and by
 * tests. A document that does not fit the protocol is refused and the last good one stays.
 *
 * @param input - The document as parsed JSON.
 * @returns True when the document was accepted.
 */
export function receive(input: unknown): boolean {
  const parsed = mirrorDocumentSchema.safeParse(input)
  if (!parsed.success) return false
  current = parsed.data
  for (const listener of listeners) listener()
  return true
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

declare global {
  interface Window {
    dwMirror?: { receive: typeof receive }
  }
}

if (typeof window !== 'undefined') window.dwMirror = { receive }

/** The Mirror: the Session's Transcript, drawn row by row. */
export function App() {
  const document = useSyncExternalStore(subscribe, () => current)
  if (!document) return <p className="empty">Waiting for the session…</p>
  return (
    <main className="transcript">
      {document.rows.map((row) => (
        <div key={row.id} className={`row row-${row.kind}`}>
          {row.kind === 'prompt' || row.kind === 'reply'
            ? row.text
            : row.kind === 'tool'
              ? row.tool
              : row.word}
        </div>
      ))}
    </main>
  )
}
