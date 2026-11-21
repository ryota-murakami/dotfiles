import { useTranscript } from './store'

/** The Mirror: the Session's Transcript, drawn row by row. */
export function App() {
  const transcript = useTranscript()
  if (!transcript) return <p className="empty">Waiting for the session…</p>
  return (
    <main className="transcript">
      {transcript.rows.map((row) => (
        <div key={row.id} className={`row row-${row.kind}`}>
          {'text' in row ? row.text : 'tool' in row ? row.tool : row.kind}
        </div>
      ))}
    </main>
  )
}
