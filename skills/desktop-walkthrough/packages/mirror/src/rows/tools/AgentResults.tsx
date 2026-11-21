/**
 * The results of the Agent and Skill tools (`tools.md`, sections 3.7 and 3.8): `Done (3 tool uses ·
 * 12k tokens · 45s)`, `Backgrounded agent`, `Loaded skill`.
 *
 * Why it exists: an agent's own work is not in the Row, only its summary line, and the terminal words
 * that line from counts the result carries. Called by {@link ToolResultView} for a finished Agent or
 * Skill call.
 */
import type { ToolCall } from '@dw/protocol'

import { Dim, Gutter } from '../../terminal'
import { Strong } from './blocks'
import { field, flagField, numberField, readList, readText, textField } from './data'
import { formatDuration } from '../duration'
import { countOf, formatSize, formatTokens } from './format'
import { describeCall } from './title'

/** Whether an Agent call is the web-fetch helper. */
function isFetchAgent(call: ToolCall): boolean {
  return describeCall(call)?.name === 'Fetch'
}

/**
 * How an agent call ended, for the group tree and the result row.
 *
 * @param call - An Agent call.
 * @returns `remote`, `async` or `completed`, by the result's `status`.
 */
export function agentLaunch(call: ToolCall): 'remote' | 'async' | 'completed' {
  const status = textField(call.output, 'status')
  if (status === 'remote_launched') return 'remote'
  if (status === 'async_launched') return 'async'
  return 'completed'
}

/**
 * The agent's finish line and, under it, the hint that the whole run is behind `ctrl+o`.
 *
 * @param props.call - The finished Agent call with its `output`.
 */
export function AgentResult({ call }: { call: ToolCall }) {
  const launch = agentLaunch(call)
  if (launch === 'remote') {
    return (
      <Gutter>
        {`Cloud agent launched · ${textField(call.output, 'taskId') ?? ''} · ${textField(call.output, 'sessionUrl') ?? ''}`}
      </Gutter>
    )
  }
  const hasPrompt =
    (readText(field(call.output, 'prompt'))?.text ?? readText(field(call.input, 'prompt'))?.text) !==
    undefined
  if (launch === 'async') {
    if (isFetchAgent(call)) return <Gutter>Fetching in background</Gutter>
    return (
      <Gutter>
        Backgrounded agent
        <Dim>{hasPrompt ? ' (↓ to manage · ctrl+o to expand)' : ' (↓ to manage)'}</Dim>
      </Gutter>
    )
  }
  if (isFetchAgent(call)) {
    const content = readList(field(call.output, 'content')).items
    const chars = content.reduce<number>(
      (sum, block) => sum + (readText(field(block, 'text'))?.chars ?? 0),
      0,
    )
    if (chars === 0) {
      return (
        <Gutter>
          Not fetched <Dim>(ctrl+o to expand)</Dim>
        </Gutter>
      )
    }
    return (
      <Gutter>
        Received <Strong>{formatSize(chars)}</Strong>
      </Gutter>
    )
  }
  const toolUses = numberField(call.output, 'totalToolUseCount')
  const tokens = numberField(call.output, 'totalTokens')
  const durationMs = numberField(call.output, 'totalDurationMs')
  const parts = [
    toolUses === undefined ? undefined : countOf(toolUses, 'tool use'),
    tokens === undefined ? undefined : `${formatTokens(tokens)} tokens`,
    durationMs !== undefined && durationMs >= 1000 ? formatDuration(durationMs) : undefined,
  ].filter((part): part is string => part !== undefined)
  return (
    <Gutter>
      <div>{parts.length > 0 ? `Done (${parts.join(' · ')})` : 'Done'}</div>
      <div>
        <Dim>{'  (ctrl+o to expand)'}</Dim>
      </div>
    </Gutter>
  )
}

/**
 * A skill call's row: `Loaded skill` with its tool count and model, or the outcome of a forked skill.
 *
 * @param props.call - The finished Skill call with its `output`.
 */
export function SkillResult({ call }: { call: ToolCall }) {
  const output = call.output
  if (textField(output, 'status') === 'forked') {
    return <Gutter>{flagField(output, 'background') ? 'Running in the background' : 'Done'}</Gutter>
  }
  const allowed = readList(field(output, 'allowedTools')).items.length
  const model = textField(output, 'model')
  return (
    <Gutter>
      Loaded skill
      {allowed > 0 && ` · ${countOf(allowed, 'tool')} allowed`}
      {model !== undefined && ` · ${model}`}
    </Gutter>
  )
}
