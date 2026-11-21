/**
 * The page's two doors to the HUD: `window.dwMirror` (the HUD calls in with documents) and
 * {@link post} (the page tells the HUD what the user did).
 *
 * Why it exists: in the HUD the page talks through WebKit's message handler; in a browser, where
 * the gallery and the tests run, there is no HUD, and what the page would have said is kept in
 * `window.dwMirrorPosted` instead so that it can be read back.
 */
import type { PageMessage } from '@dw/protocol'

import { focusInput } from './live/inputHandle'
import { receiveLive, receiveTranscript } from './store'

declare global {
  interface Window {
    /** Called by the HUD with what the Bridge wrote. */
    dwMirror?: {
      receiveTranscript: typeof receiveTranscript
      receiveLive: typeof receiveLive
      /** Put the keyboard in the Input box. */
      focusInput: typeof focusInput
    }
    /** What the page said while no HUD was listening. */
    dwMirrorPosted?: PageMessage[]
    webkit?: { messageHandlers?: { dw?: { postMessage: (message: PageMessage) => void } } }
  }
}

/** Open the door the HUD calls in through. Called once, when the page starts. */
export function installHost() {
  window.dwMirror = { receiveTranscript, receiveLive, focusInput }
  post({ type: 'ready' })
}

/**
 * Tell the HUD what the user did in the Mirror.
 *
 * @param message - A Prompt sent, an interrupt, the Input box's focus or draft.
 */
export function post(message: PageMessage) {
  const handler = window.webkit?.messageHandlers?.dw
  if (handler) {
    handler.postMessage(message)
    return
  }
  // No HUD (a browser, a test): keep it where it can be read back
  window.dwMirrorPosted = [...(window.dwMirrorPosted ?? []), message]
}
