import type { LiveDocument } from '@dw/protocol'

import { Dim, themeColor, type ThemeColorName } from '../terminal'

/** The permission-mode pills, as the terminal words them, with the colour each is drawn in. */
const MODE_PILLS: readonly (readonly [string, ThemeColorName])[] = [
  ['⏸ plan mode on', 'planMode'],
  ['⏵⏵ accept edits on', 'autoAccept'],
  ['⏵⏵ bypass permissions on', 'error'],
  ['⏵⏵ don’t ask on', 'error'],
  ["⏵⏵ don't ask on", 'error'],
  ['⏵⏵ auto mode on', 'warning'],
]

/** Hint items that are about the terminal's own input and say nothing true while the Mirror's box holds a draft. */
const HIDDEN_WHILE_DRAFT = new Set(['? for shortcuts', 'esc to interrupt'])

/**
 * Cut the terminal's hint line into the items it joins with ` · `.
 *
 * @param hint - The hint as the terminal words it.
 * @param hasDraft - True while the Input box holds text: the items that only make sense for an empty box go.
 */
export function hintItems(hint: string, hasDraft: boolean): string[] {
  return hint
    .split(' · ')
    .filter((item) => item !== '' && !(hasDraft && HIDDEN_WHILE_DRAFT.has(item.trim().toLowerCase())))
}

/** One hint item: a known pill or the background-tasks count in its own colour, the rest dim. */
function HintItem({ item }: { item: string }) {
  const pill = MODE_PILLS.find(([text]) => item.startsWith(text))
  if (pill) {
    return (
      <>
        <span style={{ color: themeColor(pill[1]) }}>{pill[0]}</span>
        <Dim>{item.slice(pill[0].length)}</Dim>
      </>
    )
  }
  const tasks = /^\d+ background tasks?/.exec(item)
  if (tasks) {
    return (
      <>
        <span style={{ color: themeColor('background') }}>{tasks[0]}</span>
        <Dim>{item.slice(tasks[0].length)}</Dim>
      </>
    )
  }
  return <Dim>{item}</Dim>
}

/**
 * The footer under the Input box: the terminal's hint line at the left and its mode labels at the right.
 *
 * Why it exists: the terminal tells the user which permission mode is on and what Esc does in a row
 * under its input; the Mirror shows the same words, as the Bridge reports them. Rendered by
 * {@link LiveArea}. The user's own status line is not in the data yet, so its place is left out.
 *
 * @param props.live - The newest live document, undefined until the HUD has handed one over.
 * @param props.hasDraft - True while the Input box holds text: the hint items about interrupting go.
 */
export function Footer({ live, hasDraft }: { live: LiveDocument | undefined; hasDraft: boolean }) {
  const items = live?.hint ? hintItems(live.hint, hasDraft) : []
  const modes = live?.modes ?? []
  return (
    <div className="footer">
      <div className="footer-hint">
        {items.map((item, index) => (
          <span key={item}>
            {index > 0 ? <Dim>{' · '}</Dim> : null}
            <HintItem item={item} />
          </span>
        ))}
      </div>
      {modes.length > 0 ? (
        <div className="footer-modes">
          <Dim>{modes.join(' · ')}</Dim>
        </div>
      ) : null}
    </div>
  )
}
