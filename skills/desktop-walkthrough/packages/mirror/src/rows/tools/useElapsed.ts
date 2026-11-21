import { useEffect, useState } from 'react'

/**
 * How long the page has seen something running.
 *
 * Why it exists: a row has no timestamps, but the terminal shows an elapsed time on a running call
 * (`Running… (12s · timeout 2m)`, the folded line's ` · 5s`); the Mirror counts from the moment the
 * page first saw the row running. Called by the running Bash result and by the folded-run line.
 *
 * @param isActive - True while the call or the group runs.
 * @returns Milliseconds since the page first saw it active, ticking once a second; undefined while inactive.
 */
export function useElapsed(isActive: boolean): number | undefined {
  const [elapsed, setElapsed] = useState<number | undefined>(undefined)
  useEffect(() => {
    if (!isActive) return
    // The count starts when the row is first seen active; the page's own clock is all there is
    const startedAt = Date.now()
    const timer = setInterval(() => setElapsed(Date.now() - startedAt), 1000)
    return () => {
      clearInterval(timer)
      setElapsed(undefined)
    }
  }, [isActive])
  return isActive ? (elapsed ?? 0) : undefined
}
