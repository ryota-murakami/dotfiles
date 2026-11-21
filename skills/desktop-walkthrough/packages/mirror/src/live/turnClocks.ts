/**
 * The page's own clocks of the running turn: when the mode became `thinking` and ended, and when the
 * response length last grew.
 *
 * Why it exists: the HUD hands the page `mode` and `responseLength` only when they change, but the
 * thinking wording and the stall rule depend on how long ago that was, so the page notes the moment it
 * saw each change. Held by {@link useTurnClocks}; the gallery builds one by replaying a timeline.
 */
import type { LiveDocument } from '@dw/protocol'

export class TurnClocks {
  /** When the turn the clocks follow began, as the HUD reported it; a different value starts over. */
  private turnStart: number | undefined
  private mode: string | undefined
  private length: number | undefined

  /** When the last growth of the response length was seen. */
  lastGrowthAt: number | undefined
  /** The latest thinking stretch: when it began and, once the mode left `thinking`, when it ended. */
  thinking: { start: number; end: number | undefined } | undefined

  /**
   * Note what a live document says, at the moment the page got it.
   *
   * Calling it again with the same values changes nothing, so a re-render may call it freely.
   *
   * @param live - The newest live document.
   * @param nowMs - Milliseconds since 1970 when the page saw it.
   */
  observe(live: LiveDocument, nowMs: number): void {
    // A turn ended, or another began: forget the old one's moments
    if (!live.isBusy || live.startedAt !== this.turnStart) {
      this.lastGrowthAt = undefined
      this.thinking = undefined
      this.mode = undefined
      this.length = undefined
    }
    this.turnStart = live.startedAt
    if (!live.isBusy) return

    const mode = live.spinner?.mode
    if (mode !== this.mode) {
      if (mode === 'thinking') this.thinking = { start: nowMs, end: undefined }
      else if (this.thinking && this.thinking.end === undefined) this.thinking.end = nowMs
      this.mode = mode
    }

    const length = live.responseLength
    // First sight starts the silence; later, only growth restarts it
    if (this.lastGrowthAt === undefined || (length !== undefined && length > (this.length ?? 0))) {
      this.lastGrowthAt = nowMs
    }
    // A figure that fell (compaction) counts as a new beginning
    if (length !== undefined && this.length !== undefined && length < this.length) this.lastGrowthAt = nowMs
    this.length = length
  }
}
