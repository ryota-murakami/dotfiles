/**
 * The controller as the Handout runs it: built into dist/controller.js, inlined by the builder and
 * allowed by the Handout's CSP through its hash.
 */
import type { WidthStore } from './controller'
import { startHandout } from './controller'

/** localStorage, or null where the browser refuses it (some refuse it for files opened from disk). */
function widthStore(): WidthStore | null {
  try {
    const storage = window.localStorage
    storage.getItem('dw-handout')
    return storage
  } catch {
    return null
  }
}

startHandout(document, widthStore())
