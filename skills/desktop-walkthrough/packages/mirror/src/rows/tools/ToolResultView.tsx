/**
 * The result block under a call row: what the call's state and its tool say should hang there.
 *
 * Why it exists: one call can be queued, running, failed, interrupted or finished, and each state
 * draws something different under the row (`tools.md`, section 3); this picks by state first and by
 * tool second. Called by {@link ToolRow} for every call row.
 */
import type { ToolCall } from '@dw/protocol'

import { Dim, Gutter } from '../../terminal'
import { AgentResult, SkillResult } from './AgentResults'
import { BashResult, RunningBash, WaitingBash } from './BashResult'
import { textField } from './data'
import { EditResult, NotebookResult, ReadResult, WriteResult } from './FileResults'
import { GenericResult, McpResult, SearchResult, WebFetchResult, WebSearchResult } from './SearchResults'
import { ErrorResult, InterruptedResult, WorktreeResult } from './StatusRows'
import { parseMcpTool } from './title'

/** Whether a tool is one of the two that run shell commands. */
export function isShellTool(tool: string): boolean {
  return tool === 'Bash' || tool === 'PowerShell'
}

/** What hangs under a running call: its progress row, for the tools that have one. */
function ProgressView({ call }: { call: ToolCall }) {
  if (isShellTool(call.tool)) return <RunningBash call={call} />
  if (parseMcpTool(call.tool)) {
    return (
      <Gutter>
        <Dim>Running…</Dim>
      </Gutter>
    )
  }
  switch (call.tool) {
    case 'WebFetch':
      return (
        <Gutter>
          <Dim>Fetching…</Dim>
        </Gutter>
      )
    case 'WebSearch':
      return (
        <Gutter>
          <Dim>{`Searching: ${textField(call.input, 'query') ?? ''}`}</Dim>
        </Gutter>
      )
    case 'Agent':
    case 'Task':
      // The agent's own tool calls are not in the Row: only the start shows
      return (
        <Gutter>
          <Dim>Initializing…</Dim>
        </Gutter>
      )
    default:
      // A tool without a progress renderer shows nothing but its marker
      return null
  }
}

/**
 * The result block of a call.
 *
 * @param props.call - The call with its flags and, once resolved, its output.
 * @returns The block; null where the terminal draws nothing under the row.
 */
export function ToolResultView({ call }: { call: ToolCall }) {
  if (call.isInterrupted) return <InterruptedResult call={call} />
  if (call.isErrored) return <ErrorResult call={call} />
  if (call.isRunning) return <ProgressView call={call} />
  // Not started: Bash says it waits, the others draw nothing
  if (call.output === undefined) return isShellTool(call.tool) ? <WaitingBash /> : null
  if (isShellTool(call.tool)) return <BashResult call={call} />
  switch (call.tool) {
    case 'Read':
      return <ReadResult call={call} />
    case 'Edit':
      return <EditResult call={call} />
    case 'Write':
      return <WriteResult call={call} />
    case 'NotebookEdit':
      return <NotebookResult call={call} />
    case 'Grep':
    case 'Glob':
      return <SearchResult call={call} />
    case 'Agent':
    case 'Task':
      return <AgentResult call={call} />
    case 'Skill':
      return <SkillResult call={call} />
    case 'WebFetch':
      return <WebFetchResult call={call} />
    case 'WebSearch':
      return <WebSearchResult call={call} />
    case 'EnterWorktree':
    case 'ExitWorktree':
      return <WorktreeResult call={call} />
    default:
      return parseMcpTool(call.tool) ? <McpResult call={call} /> : <GenericResult call={call} />
  }
}
