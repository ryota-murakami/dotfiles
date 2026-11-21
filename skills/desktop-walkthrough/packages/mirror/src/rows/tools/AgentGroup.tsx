/**
 * The folded run of several agents started together: a header that counts them and a tree with one
 * entry per agent (`tools.md`, section 3.7).
 *
 * Why it exists: agent calls do not fold into the `read 2 files` line; the terminal draws a small tree
 * so that parallel agents can be told apart. Called by {@link ToolGroupRow} when every call of the
 * group is an Agent call.
 */
import type { ToolCall } from '@dw/protocol'

import { Dim, GLYPH, RowLayout, themeColor } from '../../terminal'
import { agentLaunch } from './AgentResults'
import { Strong } from './blocks'
import { nounFor } from './format'
import { MARKER_COLOR } from './marker'
import { hasFailed } from './group'
import { describeCall } from './title'

/** How one agent of the group stands, in the word the tree shows. */
function outcomeOf(call: ToolCall): string {
  if (call.isInterrupted) return 'interrupted'
  if (hasFailed(call)) return 'failed'
  if (call.isRunning) return 'Initializing…'
  if (call.output === undefined) return 'no result recorded'
  return 'done'
}

/**
 * The agent tree.
 *
 * @param props.calls - The group's Agent calls, in the order the model made them.
 * @param props.isActive - True while the group runs.
 */
export function AgentGroup({ calls, isActive }: { calls: readonly ToolCall[]; isActive: boolean }) {
  const running = calls.filter((call) => call.isRunning || (isActive && call.output === undefined)).length
  const finished = calls.length - running
  const asyncOnly = calls.every((call) => agentLaunch(call) === 'async')
  const titles = calls.map((call) => describeCall(call))
  const sharedType = titles.every((title) => title?.name === titles[0]?.name) ? titles[0]?.name : undefined
  const typeWord = sharedType !== undefined && sharedType !== 'Agent' ? `${sharedType} ` : ''
  const noun = `${typeWord}${nounFor(calls.length, 'agent')}`
  let header
  if (running > 0) {
    header = (
      <>
        Running <Strong>{finished > 0 ? `${finished} of ${calls.length}` : calls.length}</Strong> {noun}…
      </>
    )
  } else if (asyncOnly) {
    header = (
      <>
        <Strong>{calls.length}</Strong> background {noun} launched <Dim>(↓ to manage)</Dim>
      </>
    )
  } else {
    header = (
      <>
        <Strong>{calls.length}</Strong> {noun} finished
      </>
    )
  }
  return (
    <div className="tool-call">
      <RowLayout
        markerColor={
          running > 0
            ? themeColor('inactive')
            : calls.some(hasFailed)
              ? MARKER_COLOR.errored
              : themeColor('inactive')
        }
        marker={running > 0 || calls.some(hasFailed) ? GLYPH.bullet : ' '}
        className={running > 0 ? 'tool-running' : ''}
      >
        {header}
      </RowLayout>
      <div className="tool-tree">
        {calls.map((call, index) => {
          const isLast = index === calls.length - 1
          const title = titles[index]
          const description = title?.summary ?? ''
          return (
            <div key={index}>
              <div className="tool-tree-row">
                <span className="tool-tree-connector">{isLast ? '└' : '├'}</span>
                <div>
                  <Strong>{title?.name ?? call.tool}</Strong>
                  {description !== '' && ` (${description})`}
                </div>
              </div>
              <div className="tool-tree-row">
                <span className="tool-tree-connector">{isLast ? ' ' : '│'}</span>
                <Dim>{`⎿  ${outcomeOf(call)}`}</Dim>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
