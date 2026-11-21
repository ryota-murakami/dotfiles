/**
 * The time source of the live area, and the hooks that read it.
 *
 * Why it exists: the Spinner line is drawn from the wall clock (glyph, light, seconds), and a spec or
 * the gallery has to say what time it is, so the page reads time through a {@link Clock} that a
 * {@link ClockContext} can replace. Used by {@link SpinnerLine} and {@link useTurnClocks}; the
 * gallery provides a driven clock.
 */
import { createContext, useContext, useEffect, useState } from 'react'

import { TurnClocks } from './turnClocks'
import type { LiveDocument } from '@dw/protocol'

/** A source of the current time and of a repeating tick. */
export type Clock = {
  /** Milliseconds since 1970. */
  now: () => number
  /**
   * Call back every `periodMs`; a driven clock also calls back when it jumps.
   *
   * @returns A function that stops it.
   */
  every: (periodMs: number, callback: () => void) => () => void
}

/** The clock of the real page: the system time and real timers. */
export const realClock: Clock = {
  now: () => Date.now(),
  every: (periodMs, callback) => {
    const id = setInterval(callback, periodMs)
    return () => clearInterval(id)
  },
}

/** The clock the live area reads; replaced by the gallery. */
export const ClockContext = createContext<Clock>(realClock)

/** The {@link TurnClocks} a gallery section built by replaying a timeline; absent on the real page. */
export const TurnClocksContext = createContext<TurnClocks | undefined>(undefined)

/**
 * The current time, refreshed every period.
 *
 * @param periodMs - Milliseconds between refreshes.
 * @returns Milliseconds since 1970 as of the last refresh.
 */
export function useNow(periodMs: number): number {
  const clock = useContext(ClockContext)
  const [now, setNow] = useState(() => clock.now())
  useEffect(() => clock.every(periodMs, () => setNow(clock.now())), [clock, periodMs])
  return now
}

/**
 * The page's clocks of the running turn, kept up to date with each live document.
 *
 * @param live - The newest live document.
 * @returns The {@link TurnClocks}, already told about `live`.
 */
export function useTurnClocks(live: LiveDocument | undefined): TurnClocks {
  const clock = useContext(ClockContext)
  const provided = useContext(TurnClocksContext)
  const [own] = useState(() => new TurnClocks())
  const clocks = provided ?? own
  // Idempotent per document, so a repeated render does not move the noted moments
  if (live) clocks.observe(live, clock.now())
  return clocks
}
