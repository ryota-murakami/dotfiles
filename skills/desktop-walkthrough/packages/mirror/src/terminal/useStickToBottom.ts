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

    let isPinned = true
    // A scroll the user made decides: at the bottom pins, anywhere else unpins
    const onScroll = () => {
      isPinned = isAtBottom(container)
    }
    // Content or container changed size: follow the end while pinned
    const follow = () => {
      if (isPinned) container.scrollTop = container.scrollHeight
    }
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
