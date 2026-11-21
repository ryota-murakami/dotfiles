/**
 * What the Mirror draws from: the newest Transcript and live state the HUD handed over.
 *
 * Why it exists: the page runs in a web view that may not read files, so the HUD reads what the
 * Bridge wrote and calls `window.dwMirror` with it. Components read the store through the two
 * hooks; a document that does not fit the protocol is refused and the last good one stays.
 */
import {
  liveDocumentSchema,
  rowSchema,
  transcriptEnvelopeSchema,
  type LiveDocument,
  type Row,
  type TranscriptDocument,
} from '@dw/protocol'
import { useSyncExternalStore } from 'react'

const state: { transcript: TranscriptDocument | undefined; live: LiveDocument | undefined } = {
  transcript: undefined,
  live: undefined,
}
const listeners = new Set<() => void>()
/** The Rows of the Transcript on show, each with the JSON it was read from. */
let kept = new Map<string, { json: string; row: Row }>()

function notify() {
  for (const listener of listeners) listener()
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/**
 * Take a Transcript from the HUD.
 *
 * @param input - The document as parsed JSON.
 * @returns True when it was accepted.
 */
export function receiveTranscript(input: unknown): boolean {
  const envelope = transcriptEnvelopeSchema.safeParse(input)
  if (!envelope.success) return false
  // A Row that reads the same as before stays the same object, so that only changed Rows are drawn again
  const next = new Map<string, { json: string; row: Row }>()
  const rows: Row[] = []
  for (const raw of envelope.data.rows) {
    const json = JSON.stringify(raw)
    const id =
      typeof raw === 'object' && raw !== null && 'id' in raw && typeof raw.id === 'string'
        ? raw.id
        : undefined
    const before = id === undefined ? undefined : kept.get(id)
    if (id !== undefined && before?.json === json) {
      rows.push(before.row)
      next.set(id, before)
      continue
    }
    const parsed = rowSchema.safeParse(raw)
    // One Row that does not fit refuses the document: the last good one stays
    if (!parsed.success) return false
    rows.push(parsed.data)
    next.set(parsed.data.id, { json, row: parsed.data })
  }
  kept = next
  state.transcript = {
    v: envelope.data.v,
    sessionId: envelope.data.sessionId,
    dropped: envelope.data.dropped,
    rows,
  }
  notify()
  return true
}

/**
 * Take a live state from the HUD.
 *
 * @param input - The document as parsed JSON.
 * @returns True when it was accepted.
 */
export function receiveLive(input: unknown): boolean {
  const parsed = liveDocumentSchema.safeParse(input)
  if (!parsed.success) return false
  state.live = parsed.data
  notify()
  return true
}

/** Forget everything received: a test starts from an empty Mirror. */
export function resetStore() {
  kept = new Map()
  state.transcript = undefined
  state.live = undefined
  notify()
}

/** The Transcript on show, read outside of a component (the specs of the store). */
export function currentTranscript(): TranscriptDocument | undefined {
  return state.transcript
}

/** The Transcript to draw, undefined until the HUD handed one over. */
export function useTranscript(): TranscriptDocument | undefined {
  return useSyncExternalStore(subscribe, () => state.transcript)
}

/** The live state to draw, undefined until the HUD handed one over. */
export function useLive(): LiveDocument | undefined {
  return useSyncExternalStore(subscribe, () => state.live)
}
