/**
 * What the Mirror draws from: the newest Transcript and live state the HUD handed over.
 *
 * Why it exists: the page runs in a web view that may not read files, so the HUD reads what the
 * Bridge wrote and calls `window.dwMirror` with it. Components read the store through the two
 * hooks; a document that does not fit the protocol is refused and the last good one stays.
 */
import {
  liveDocumentSchema,
  transcriptDocumentSchema,
  type LiveDocument,
  type TranscriptDocument,
} from '@dw/protocol'
import { useSyncExternalStore } from 'react'

const state: { transcript: TranscriptDocument | undefined; live: LiveDocument | undefined } = {
  transcript: undefined,
  live: undefined,
}
const listeners = new Set<() => void>()

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
  const parsed = transcriptDocumentSchema.safeParse(input)
  if (!parsed.success) return false
  state.transcript = parsed.data
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
  state.transcript = undefined
  state.live = undefined
  notify()
}

/** The Transcript to draw, undefined until the HUD handed one over. */
export function useTranscript(): TranscriptDocument | undefined {
  return useSyncExternalStore(subscribe, () => state.transcript)
}

/** The live state to draw, undefined until the HUD handed one over. */
export function useLive(): LiveDocument | undefined {
  return useSyncExternalStore(subscribe, () => state.live)
}
