/**
 * The wording of a folded run of tool calls: which clauses the line has, in which order, with which
 * verbs (`tools.md`, section 4).
 *
 * Why it exists: `Searched for 3 patterns, read 2 files` is computed from the calls' kinds and states,
 * live (`Searching for 3 patterns, reading 2 files…`) or done; keeping it a pure function keeps the
 * component free of the rules and lets a spec pin the wording. Called by {@link ToolGroupRow}.
 */
import type { ToolCall } from '@dw/protocol'

import { field, isRecord, numberField, readText, textField } from './data'
import { countChanges } from './Diff'
import { displayPath, nounFor } from './format'
import { isRowlessTool, parseMcpTool } from './title'

/** A piece of a clause; counts are bold. */
export type GroupPart = { text: string; isBold?: boolean }

/** One clause of the line: `read 2 files`. */
export type GroupClause = GroupPart[]

/** What the line says about a run of calls. */
export type GroupSummary = {
  clauses: GroupClause[]
  /** Calls that ended in an error: the line adds ` N failed`. */
  failed: number
}

/** The kinds a folded call can be of. */
type CallKind = 'edit' | 'git' | 'search' | 'read' | 'list' | 'mcp' | 'agent' | 'shell' | 'other'

/**
 * Which kind of clause a call belongs to.
 *
 * @param call - A call of the group.
 * @returns Its kind; shell commands that only read, search or list files count as those.
 */
export function kindOf(call: ToolCall): CallKind {
  switch (call.tool) {
    case 'Edit':
    case 'Write':
    case 'NotebookEdit':
      return 'edit'
    case 'Read':
      return 'read'
    case 'Grep':
    case 'Glob':
      return 'search'
    case 'Agent':
    case 'Task':
      return 'agent'
    case 'Bash':
    case 'PowerShell': {
      if (isRecord(field(call.output, 'gitOperation'))) return 'git'
      const word = /^\s*([A-Za-z0-9_.-]+)/.exec(textField(call.input, 'command') ?? '')?.[1]
      if (word !== undefined && /^(ls|tree|eza|exa)$/.test(word)) return 'list'
      if (word !== undefined && /^(grep|rg|ag|ack|find|fd)$/.test(word)) return 'search'
      if (word !== undefined && /^(cat|head|tail|bat|less)$/.test(word)) return 'read'
      return 'shell'
    }
    default:
      return parseMcpTool(call.tool) ? 'mcp' : 'other'
  }
}

/** What identifies the thing a call looked at, so that reading one file twice counts once. */
function targetOf(call: ToolCall): string {
  return (
    textField(call.input, 'file_path') ??
    textField(call.input, 'notebook_path') ??
    textField(call.input, 'path') ??
    textField(call.input, 'command') ??
    call.tool
  )
}

/** How many different things a run of calls looked at. */
function distinct(group: readonly ToolCall[]): number {
  return new Set(group.map(targetOf)).size
}

/** A clause of a verb, a bold count and a noun. */
function counted(verb: string, count: number, noun: string): GroupClause {
  return [{ text: `${verb} ` }, { text: String(count), isBold: true }, { text: ` ${noun}` }]
}

/** The clauses of the git operations a Bash call reported. */
function gitClauses(calls: readonly ToolCall[]): GroupClause[] {
  const clauses: GroupClause[] = []
  for (const call of calls) {
    const operation = field(call.output, 'gitOperation')
    const commit = field(operation, 'commit')
    const push = field(operation, 'push')
    const branch = field(operation, 'branch')
    const pr = field(operation, 'pr')
    const sha = textField(commit, 'sha')?.slice(0, 7)
    if (sha !== undefined) {
      const kind = textField(commit, 'kind')
      const lead =
        kind === 'amended' ? 'amended commit ' : kind === 'cherry-picked' ? 'cherry-picked ' : 'committed '
      clauses.push([{ text: lead }, { text: sha, isBold: true }])
    }
    const pushed = textField(push, 'branch')
    if (pushed !== undefined) clauses.push([{ text: 'pushed to ' }, { text: pushed, isBold: true }])
    const ref = textField(branch, 'ref')
    if (ref !== undefined) {
      const rebased = textField(branch, 'action') === 'rebased'
      clauses.push([{ text: rebased ? 'rebased onto ' : 'merged ' }, { text: ref, isBold: true }])
    }
    const number = numberField(pr, 'number')
    if (number !== undefined) {
      const action = textField(pr, 'action') ?? 'edited'
      const words: Record<string, string> = {
        created: 'created',
        edited: 'edited',
        merged: 'merged',
        commented: 'commented on',
        closed: 'closed',
        reopened: 'reopened',
        ready: 'marked ready',
        draft: 'marked draft',
        'auto-merge-enabled': 'enabled auto-merge on',
        'auto-merge-disabled': 'disabled auto-merge on',
      }
      clauses.push([{ text: `${words[action] ?? action} PR ` }, { text: `#${number}`, isBold: true }])
    }
  }
  return clauses
}

/** How many lines a finished edit call added and removed. */
function editLines(call: ToolCall): { added: number; removed: number } {
  const patch = countChanges(field(call.output, 'structuredPatch'))
  if (patch.added + patch.removed > 0) return patch
  // A created file has no patch: all its lines are added
  if (textField(call.output, 'type') === 'create') {
    return { added: readText(field(call.output, 'content'))?.lines ?? 0, removed: 0 }
  }
  return patch
}

/**
 * Work out the line of a folded run.
 *
 * @param calls - The calls in the order the model made them.
 * @param isActive - True while the group runs: verbs are in the progressive form.
 * @returns The clauses in the terminal's order, and the number of failed calls.
 */
export function summarizeGroup(calls: readonly ToolCall[], isActive: boolean): GroupSummary {
  // Calls that draw no row of their own do not count
  const visible = calls.filter((call) => !isRowlessTool(call.tool))
  const notRun = visible.filter(
    (call) =>
      call.isInterrupted || (!isActive && !call.isRunning && !call.isErrored && call.output === undefined),
  )
  const live = visible.filter((call) => !notRun.includes(call))
  const failed = live.filter((call) => call.isErrored).length
  const ofKind = (kind: CallKind) => live.filter((call) => kindOf(call) === kind)
  const clauses: GroupClause[] = []

  const edits = ofKind('edit')
  if (edits.length > 0) {
    const totals = edits.reduce(
      (sum, call) => {
        const lines = editLines(call)
        return { added: sum.added + lines.added, removed: sum.removed + lines.removed }
      },
      { added: 0, removed: 0 },
    )
    const files = distinct(edits)
    const clause = counted(isActive ? 'editing' : 'edited', files, nounFor(files, 'file'))
    if (totals.added + totals.removed > 0) clause.push({ text: ` +${totals.added} -${totals.removed}` })
    clauses.push(clause)
  }
  clauses.push(...gitClauses(ofKind('git')))
  const searches = ofKind('search')
  if (searches.length > 0) {
    clauses.push(
      counted(
        isActive ? 'searching for' : 'searched for',
        searches.length,
        nounFor(searches.length, 'pattern'),
      ),
    )
  }
  const reads = ofKind('read')
  if (reads.length > 0) {
    const files = distinct(reads)
    clauses.push(counted(isActive ? 'reading' : 'read', files, nounFor(files, 'file')))
  }
  const lists = ofKind('list')
  if (lists.length > 0) {
    clauses.push(
      counted(
        isActive ? 'listing' : 'listed',
        lists.length,
        nounFor(lists.length, 'directory', 'directories'),
      ),
    )
  }
  const mcps = ofKind('mcp')
  if (mcps.length > 0) {
    const servers = [...new Set(mcps.map((call) => parseMcpTool(call.tool)?.server ?? call.tool))]
    const clause: GroupClause = [{ text: `${isActive ? 'calling' : 'called'} ${servers.join(', ')}` }]
    if (mcps.length > 1)
      clause.push({ text: ' ' }, { text: String(mcps.length), isBold: true }, { text: ' times' })
    clauses.push(clause)
  }
  const agents = ofKind('agent')
  if (agents.length > 0) {
    const verb = isActive ? 'running' : 'ran'
    const description = agents.length === 1 ? textField(agents[0]?.input, 'description') : undefined
    clauses.push(
      description !== undefined && description !== ''
        ? [{ text: `${verb} agent · ` }, { text: description.replaceAll(/\s+/g, ' ').trim(), isBold: true }]
        : counted(verb, agents.length, nounFor(agents.length, 'agent')),
    )
  }
  const others = ofKind('other')
  if (others.length > 0)
    clauses.push(counted(isActive ? 'calling' : 'called', others.length, nounFor(others.length, 'tool')))
  const shells = ofKind('shell')
  if (shells.length > 0) {
    clauses.push(
      counted(isActive ? 'running' : 'ran', shells.length, nounFor(shells.length, 'shell command')),
    )
  }
  if (notRun.length > 0) {
    const interrupted = notRun.some((call) => call.isInterrupted)
    const lead = interrupted ? 'did not run' : 'no result recorded for'
    // After other clauses the calls are "other calls"
    const noun = clauses.length > 0 ? nounFor(notRun.length, 'other call') : nounFor(notRun.length, 'call')
    clauses.push(counted(lead, notRun.length, noun))
  }
  return { clauses, failed }
}

/**
 * The hint under an active line: the item the latest call works on.
 *
 * @param calls - The group's calls.
 * @returns The last file read, the last pattern searched in quotes, or the first two lines of the last shell command; undefined when there is none.
 */
export function latestDetail(calls: readonly ToolCall[]): string | undefined {
  for (const call of calls.toReversed()) {
    const kind = kindOf(call)
    if (kind === 'read') {
      const path = textField(call.input, 'file_path')
      if (path !== undefined) return displayPath(path)
    }
    if (kind === 'search' || kind === 'list') {
      const pattern = textField(call.input, 'pattern')
      if (pattern !== undefined) return `"${pattern}"`
    }
    if (kind === 'shell' || kind === 'read' || kind === 'search' || kind === 'list') {
      const command = readText(field(call.input, 'command'))
      if (command) {
        const lines = command.text.split('\n')
        const head = lines.slice(0, 2).join('\n')
        return command.isClipped || lines.length > 2 ? `${head}…` : head
      }
    }
  }
  return undefined
}

/**
 * Whether a call counts as having failed, for the tree and the line alike.
 *
 * @param call - A call.
 * @returns True when the call is errored and not interrupted.
 */
export function hasFailed(call: ToolCall): boolean {
  return call.isErrored && !call.isInterrupted
}
