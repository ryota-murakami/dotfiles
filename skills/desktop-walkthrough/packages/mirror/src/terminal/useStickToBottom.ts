import { useCallback, useEffect, useRef, type RefCallback } from 'react'

/** How close to the bottom, in pixels, still counts as being at the bottom. */
const BOTTOM_TOLERANCE_PX = 4

/**
 * Whether a scroll container shows its bottom edge.
 *
 * @param element - The scroll container.
 * @returns True when it is scrolled to the end, within a few pixels.
 */
export function isAtBottom(element: HTMLElement): boolean {
  return element.scrollHeight - element.scrollTop - element.clientHeight <= BOTTOM_TOLERANCE_PX
}

/** The part of a scroll container the pin reads and moves. */
export type Scrollable = Pick<HTMLElement, 'scrollTop' | 'scrollHeight' | 'clientHeight'>

/**
 * The rule that keeps a scroll container at its bottom: it follows the end until the reader moves away.
 *
 * Why it exists: the container tells every scroll with the same event, the reader's and the pin's own,
 * and the pin's own arrives a frame late, when a new Row may already have made the content taller. Taken
 * for the reader's, that event would unpin the Mirror while nobody scrolled. So the pin remembers
 * where it put the container and ignores the event that reports that place. Used by
 * {@link useStickToBottom}.
 *
 * @param container - The scroll container.
 * @returns `follow` to call when the content or the container changed size, `onScroll` for its scroll event.
 */
export function createPin(container: Scrollable): { follow: () => void; onScroll: () => void } {
  let isPinned = true
  // Where the pin's own last scroll put the container
  let ownTop = -1
  return {
    follow() {
      if (!isPinned) return
      container.scrollTop = container.scrollHeight
      ownTop = container.scrollTop
    },
    onScroll() {
      // While pinned, the report of the place the pin itself chose is not the reader's doing
      if (isPinned && Math.abs(container.scrollTop - ownTop) <= 1) return
      // The reader scrolled: at the bottom pins, anywhere else unpins
      isPinned = container.scrollHeight - container.scrollTop - container.clientHeight <= BOTTOM_TOLERANCE_PX
    },
  }
}

/**
 * Keeps a scroll container pinned to its bottom while its content grows, until the reader scrolls up.
 *
 * Why it exists: new Rows arrive while the user reads; the newest must stay in view like in a terminal,
 * but a reader who scrolled up to look at something must not be pulled away. Scrolling back to the
 * bottom pins it again. Used by {@link App} on the transcript's scroll container.
 *
 * @returns A ref callback for the scroll container; its first child is the content that grows.
 */
export function useStickToBottom(): RefCallback<HTMLElement> {
  const cleanupRef = useRef<(() => void) | undefined>(undefined)

  useEffect(() => () => cleanupRef.current?.(), [])

  return useCallback((container: HTMLElement | null) => {
    cleanupRef.current?.()
    cleanupRef.current = undefined
    if (!container) return

    // Content or container changed size: follow the end while pinned; a scroll the reader made decides
    const { follow, onScroll } = createPin(container)
    container.addEventListener('scroll', onScroll, { passive: true })
    const observer = new ResizeObserver(follow)
    // The content element can be replaced (the empty notice gives way to the transcript): watch the new one
    const watch = () => {
      observer.disconnect()
      observer.observe(container)
      if (container.firstElementChild) observer.observe(container.firstElementChild)
      follow()
    }
    const replacement = new MutationObserver(watch)
    replacement.observe(container, { childList: true })
    watch()

    cleanupRef.current = () => {
      container.removeEventListener('scroll', onScroll)
      observer.disconnect()
      replacement.disconnect()
    }
  }, [])
}
