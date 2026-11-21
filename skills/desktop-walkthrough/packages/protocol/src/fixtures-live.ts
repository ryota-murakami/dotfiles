/**
 * Sample turns for the Mirror's live area: the Spinner line, the Input box's footer and the moments in
 * between, invented content. Used by the gallery, which plays them on a driven clock, and by specs.
 */
import type { LiveDocument } from './index'

/** The moment every sample turn began, in milliseconds since 1970. */
export const SAMPLE_TURN_STARTED_AT = 1_795_000_000_000

/** One live document and when, in seconds into the turn, the HUD would have handed it over. */
export type LiveStep = { atSeconds: number; live: LiveDocument }

/** A named moment of a turn for the gallery: the documents in the order they arrived and where to look. */
export type LiveFixture = {
  title: string
  /** What to check it against in the terminal. */
  note: string
  /** The documents, oldest first; the one shown is the newest whose `atSeconds` has passed. */
  timeline: readonly LiveStep[]
  /** Seconds into the turn the gallery starts at. */
  showAtSeconds: number
}

/** A busy live document of the sample turn. */
function busy(fields: Omit<LiveDocument, 'v' | 'isBusy' | 'startedAt'>): LiveDocument {
  return { v: 1, isBusy: true, startedAt: SAMPLE_TURN_STARTED_AT, ...fields }
}

const WORKING_HINT = 'esc to interrupt'

export const liveFixtures: readonly LiveFixture[] = [
  {
    title: 'Spinner: request just sent',
    note: 'Light runs left to right, fast; no bracket yet (no tokens, under 16 s, not thinking).',
    showAtSeconds: 3,
    timeline: [
      {
        atSeconds: 0,
        live: busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'requesting' }, hint: WORKING_HINT }),
      },
    ],
  },
  {
    title: 'Spinner: waiting 20 s with nothing back',
    note: 'The bracket shows the time alone once 16 s have passed (`(20s)`). Stall starts at 10 s of silence and turns the line red by 20 s.',
    showAtSeconds: 20,
    timeline: [
      {
        atSeconds: 0,
        live: busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'requesting' }, hint: WORKING_HINT }),
      },
    ],
  },
  {
    title: 'Spinner: thinking for 12 s',
    note: 'Text `still thinking with max effort` pulses between two greys and has begun to tint toward yellow; the light runs right to left, slowly.',
    showAtSeconds: 13,
    timeline: [
      {
        atSeconds: 0,
        live: busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'requesting' }, hint: WORKING_HINT }),
      },
      {
        atSeconds: 1,
        live: busy({
          spinner: { word: 'Puzzling', suffix: '…', mode: 'thinking' },
          responseLength: 640,
          effort: 'max',
          hint: WORKING_HINT,
        }),
      },
    ],
  },
  {
    title: 'Spinner: thinking for 50 s',
    note: '`deep in thought`, fully tinted yellow; the glyph is bold.',
    showAtSeconds: 51,
    timeline: [
      {
        atSeconds: 0,
        live: busy({
          spinner: { word: 'Cogitating', suffix: '…', mode: 'thinking' },
          responseLength: 1_200,
          effort: 'xhigh',
          hint: WORKING_HINT,
        }),
      },
    ],
  },
  {
    title: 'Spinner: thought for 8 s',
    note: 'Thinking ended at 9 s; `thought for 8s` stays two seconds (scrub from 9 to 11 s), then disappears.',
    showAtSeconds: 10,
    timeline: [
      {
        atSeconds: 1,
        live: busy({
          spinner: { word: 'Puzzling', suffix: '…', mode: 'thinking' },
          responseLength: 400,
          effort: 'high',
          hint: WORKING_HINT,
        }),
      },
      {
        atSeconds: 9,
        live: busy({
          spinner: { word: 'Puzzling', suffix: '…', mode: 'responding' },
          responseLength: 2_000,
          effort: 'high',
          hint: WORKING_HINT,
        }),
      },
    ],
  },
  {
    title: 'Spinner: 40 s and 5.2k tokens',
    note: 'Bracket `(40s · ↓ 5.2k tokens)`; the figure counts up when it grows (play from 36 s).',
    showAtSeconds: 40,
    timeline: [
      {
        atSeconds: 0,
        live: busy({ spinner: { word: 'Puzzling', suffix: '…', mode: 'requesting' }, hint: WORKING_HINT }),
      },
      {
        atSeconds: 37,
        live: busy({
          spinner: { word: 'Puzzling', suffix: '…', mode: 'responding' },
          responseLength: 20_800,
          hint: WORKING_HINT,
        }),
      },
    ],
  },
  {
    title: 'Spinner: stalled for 25 s',
    note: 'Nothing has been written for 25 s: glyph and verb are red and the light has stopped.',
    showAtSeconds: 30,
    timeline: [
      {
        atSeconds: 3,
        live: busy({
          spinner: { word: 'Puzzling', suffix: '…', mode: 'responding' },
          responseLength: 3_400,
          hint: WORKING_HINT,
        }),
      },
    ],
  },
  {
    title: 'Spinner: a tool runs, 42 s',
    note: 'No travelling light: the whole word breathes between the two oranges.',
    showAtSeconds: 42,
    timeline: [
      {
        atSeconds: 0,
        live: busy({
          spinner: { word: 'Puzzling', suffix: '…', mode: 'tool-use' },
          responseLength: 5_200,
          effort: 'high',
          hint: WORKING_HINT,
        }),
      },
    ],
  },
  {
    title: 'Footer: working with modes',
    note: 'Pill in its mode colour, background tasks in cyan, the rest dim; mode labels at the right.',
    showAtSeconds: 65,
    timeline: [
      {
        atSeconds: 64,
        live: busy({
          spinner: { word: 'Wrangling', suffix: '…', mode: 'responding' },
          responseLength: 338_400,
          hint: '⏵⏵ bypass permissions on · 4 background tasks · esc to interrupt',
          modes: ['focus', 'memory paused'],
        }),
      },
    ],
  },
  {
    title: 'Idle: waiting for a Prompt',
    note: 'No spinner line; the box and `? for shortcuts`. Type in the box to see the draft hide the hint.',
    showAtSeconds: 0,
    timeline: [{ atSeconds: 0, live: { v: 1, isBusy: false, hint: '? for shortcuts' } }],
  },
  {
    title: 'Idle: accept-edits mode',
    note: 'The pill alone, in the purple of accept-edits.',
    showAtSeconds: 0,
    timeline: [
      { atSeconds: 0, live: { v: 1, isBusy: false, hint: '⏵⏵ accept edits on (shift+tab to cycle)' } },
    ],
  },
]
