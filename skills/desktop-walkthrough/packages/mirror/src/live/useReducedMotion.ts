import { useEffect, useState } from 'react'

const QUERY = '(prefers-reduced-motion: reduce)'

/**
 * Whether the user asked their system for reduced motion.
 *
 * Why it exists: the terminal swaps the Spinner line's glyph frames, travelling light and counting
 * animation for a still `●` that pulses when the user asks for less motion; the page follows the
 * system setting. Called by {@link SpinnerLine}.
 *
 * @returns True while the system asks for reduced motion; follows changes.
 */
export function useReducedMotion(): boolean {
  const [isReduced, setReduced] = useState(() => matches())
  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return
    const list = window.matchMedia(QUERY)
    const update = () => setReduced(list.matches)
    list.addEventListener('change', update)
    return () => list.removeEventListener('change', update)
  }, [])
  return isReduced
}

function matches(): boolean {
  return typeof window.matchMedia === 'function' && window.matchMedia(QUERY).matches
}
