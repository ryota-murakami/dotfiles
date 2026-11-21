import type { LiveDocument } from '@dw/protocol'
import { liveFixtures, type LiveFixture } from '@dw/protocol/fixtures-live'
import { useEffect, useLayoutEffect, useMemo, useState } from 'react'

import { ClockContext, TurnClocksContext, type Clock } from './clock'
import { LiveArea } from './LiveArea'
import { TurnClocks } from './turnClocks'
import './liveGallery.css'

/** The widths, in columns, every live fixture is drawn at. */
const WIDTHS = [110, 60] as const

/** Real milliseconds between two steps while a section plays. */
const PLAY_STEP_MS = 50

/**
 * A clock the gallery drives by hand: its time is the turn's start plus the seconds the section is at.
 *
 * Why it exists: to show "thinking for 12 s" or "stalled" without waiting, the section tells the live
 * area what time it is. Callbacks registered with `every` run whenever the time is set.
 */
function createDrivenClock(
  startedAt: number,
): Clock & { set: (seconds: number) => void; notify: () => void } {
  let now = startedAt
  const listeners = new Set<() => void>()
  return {
    now: () => now,
    every: (_periodMs, callback) => {
      listeners.add(callback)
      return () => listeners.delete(callback)
    },
    // Moving the time is silent, so that the render that follows reads the new time...
    set: (seconds) => {
      now = startedAt + seconds * 1000
    },
    // ...and the listeners are told once it has been drawn
    notify: () => {
      for (const listener of listeners) listener()
    },
  }
}

/** The documents that have arrived by a moment, and the page's clocks as they would stand then. */
function replay(fixture: LiveFixture, startedAt: number, seconds: number) {
  const clocks = new TurnClocks()
  let live: LiveDocument = { v: 1, isBusy: false }
  for (const step of fixture.timeline) {
    if (step.atSeconds > seconds) break
    live = step.live
    clocks.observe(step.live, startedAt + step.atSeconds * 1000)
  }
  return { live, clocks }
}

/** One fixture: a slider for the seconds into the turn, a play button and the live area at two widths. */
function LiveSection({ fixture }: { fixture: LiveFixture }) {
  const startedAt = fixture.timeline[0]?.live.startedAt ?? 0
  const [seconds, setSeconds] = useState(fixture.showAtSeconds)
  const [isPlaying, setPlaying] = useState(false)
  const clock = useMemo(() => createDrivenClock(startedAt), [startedAt])
  const { live, clocks } = useMemo(() => replay(fixture, startedAt, seconds), [fixture, startedAt, seconds])

  // The live area reads the time while it renders: set it first, and tell its timers afterwards
  clock.set(seconds)
  // `seconds` is not read inside: it is what makes the timers need telling
  // oxlint-disable-next-line react/exhaustive-effect-dependencies
  useLayoutEffect(() => clock.notify(), [clock, seconds])
  useEffect(() => {
    if (!isPlaying) return
    const id = setInterval(() => setSeconds((current) => current + PLAY_STEP_MS / 1000), PLAY_STEP_MS)
    return () => clearInterval(id)
  }, [isPlaying])

  return (
    <section className="gallery-section" id={fixture.title.toLowerCase().replaceAll(/[^a-z0-9]+/g, '-')}>
      <h2 className="gallery-title">{fixture.title}</h2>
      <p className="gallery-note">{fixture.note}</p>
      <div className="gallery-time">
        <button type="button" onClick={() => setPlaying((playing) => !playing)}>
          {isPlaying ? 'Pause' : 'Play'}
        </button>
        <input
          type="range"
          min={0}
          max={90}
          step={0.1}
          value={seconds}
          aria-label="Seconds into the turn"
          onChange={(event) => setSeconds(Number(event.target.value))}
        />
        <span>{seconds.toFixed(1)} s into the turn</span>
      </div>
      <div className="gallery-frames">
        {WIDTHS.map((columns) => (
          <div key={columns}>
            <div className="gallery-caption">{columns} columns</div>
            <div className="gallery-frame" style={{ width: `${columns}ch` }} data-columns={columns}>
              <ClockContext value={clock}>
                <TurnClocksContext value={clocks}>
                  <LiveArea live={live} />
                </TurnClocksContext>
              </ClockContext>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}

/**
 * The live area's gallery: each sample turn of the protocol's live fixtures at two widths, with a
 * clock you drive, to check the Spinner line, the Input box and the footer in a browser.
 *
 * Why it exists: the Spinner line depends on how long things have lasted, which cannot be shown from a
 * still document. Rendered by the development gallery (`gallery/main.tsx`); not part of the built page.
 */
export function LiveGallery() {
  return (
    <>
      {liveFixtures.map((fixture) => (
        <LiveSection key={fixture.title} fixture={fixture} />
      ))}
    </>
  )
}
