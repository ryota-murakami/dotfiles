/**
 * The title of a tool call row: its display name and the argument summary in parentheses, by tool.
 *
 * Why it exists: `tools.md` (section 2) gives, per tool, the name the terminal shows and what goes
 * inside the parentheses; this is that table as code. Called by {@link ToolCallRow} for every call row
 * and by the folded-run code to find which calls draw nothing.
 */
import type { ToolCall } from '@dw/protocol'

import { field, isMore, numberField, readList, readText, textField } from './data'
import { collapseSpace, displayPath } from './format'

/** What a call row's title is made of. */
export type CallTitle = {
  /** Drawn bold, never shrunk. */
  name: string
  /** Drawn in parentheses right after the name; an empty summary draws no parentheses. */
  summary: string
  /** A dim tag after the closing parenthesis (the Agent tool's model name). */
  tag?: string
}

/** Tools whose call draws no row: their name is empty or their summary is null in the terminal. */
const ROWLESS_TOOLS: ReadonlySet<string> = new Set([
  'TodoWrite',
  'TaskCreate',
  'TaskUpdate',
  'TaskGet',
  'TaskList',
  'ToolSearch',
  'AskUserQuestion',
  'EnterPlanMode',
  'ExitPlanMode',
])

/** The most characters of a Bash command's summary. */
const BASH_SUMMARY_CHARS = 160
/** The most lines of a Bash command's summary. */
const BASH_SUMMARY_LINES = 2
/** The longest argument value in an MCP or fallback summary. */
const VALUE_CHARS = 80

/**
 * Whether a tool's call draws no row of its own.
 *
 * @param tool - The tool's name.
 * @returns True for the todo and task tools, the tool search and the question and plan tools.
 */
export function isRowlessTool(tool: string): boolean {
  return ROWLESS_TOOLS.has(tool)
}

/**
 * The tool name split into the MCP server and the server's own tool name.
 *
 * @param tool - A tool name.
 * @returns The two parts for `mcp__<server>__<tool>`; undefined for any other name.
 */
export function parseMcpTool(tool: string): { server: string; name: string } | undefined {
  const match = /^mcp__([^_](?:.*?[^_])?)__(.+)$/.exec(tool)
  return match?.[1] && match[2] ? { server: match[1], name: match[2] } : undefined
}

/**
 * Cut a Bash command down to what its title shows.
 *
 * @param command - The command, whole or clipped.
 * @returns The first two lines, at most 160 characters; trimmed and ended with `…` when something was left out.
 */
export function bashSummary(command: ReturnType<typeof readText>): string {
  if (!command) return ''
  const lines = command.text.split('\n')
  let text = lines.slice(0, BASH_SUMMARY_LINES).join('\n')
  // The Bridge's own cut counts as a cut too: the head may be all there is of a long command
  let isCut = command.isClipped || lines.length > BASH_SUMMARY_LINES
  if (text.length > BASH_SUMMARY_CHARS) {
    text = text.slice(0, BASH_SUMMARY_CHARS)
    isCut = true
  }
  return isCut ? `${text.trimEnd()}…` : text
}

/**
 * An input value as JSON for a summary, with the Bridge's cut forms made plain.
 *
 * @param value - Any input value.
 * @returns JSON text; a {@link Clipped} text becomes its head and a cut list ends with `…`.
 */
function plainJson(value: unknown): string {
  const flatten = (item: unknown): unknown => {
    const text = readText(item)
    if (text && text.isClipped) return `${text.text}…`
    if (Array.isArray(item)) {
      const { items, more } = readList(item)
      return more > 0 ? [...items.map(flatten), '…'] : items.map(flatten)
    }
    if (typeof item === 'object' && item !== null && !isMore(item)) {
      return Object.fromEntries(Object.entries(item).map(([key, inner]) => [key, flatten(inner)]))
    }
    return item
  }
  return JSON.stringify(flatten(value)) ?? 'null'
}

/**
 * Every input key as `key: <JSON value>`, joined by commas, the way MCP and unknown tools summarize.
 *
 * @param input - The call's input.
 * @returns The summary; empty when the input has no keys.
 */
function keyValueSummary(input: unknown): string {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) return ''
  return Object.entries(input)
    .map(([key, value]) => {
      const json = plainJson(value)
      return `${key}: ${json.length > VALUE_CHARS ? `${json.slice(0, VALUE_CHARS)}…` : json}`
    })
    .join(', ')
}

/**
 * Whether a path is a Claude Code plan file.
 *
 * @param path - A file path.
 * @returns True for a markdown file in a `.claude/plans` folder.
 */
function isPlanFile(path: string): boolean {
  return /\/\.claude\/plans\/[^/]+\.md$/.test(path)
}

/**
 * The model names of an Agent call, for the dim tag after its title.
 *
 * @param output - The agent's result.
 * @returns The name, or `a → b` when several models were used; undefined when none is known.
 */
function agentModels(output: unknown): string | undefined {
  const used = readList(field(output, 'modelsUsed')).items.filter(
    (model): model is string => typeof model === 'string',
  )
  if (used.length > 0) return used.join(' → ')
  return textField(output, 'resolvedModel')
}

/**
 * The title of a call row.
 *
 * @param call - The call with its input and, once resolved, its output.
 * @returns The name and summary; null when the terminal draws no row for this call.
 */
export function describeCall(call: ToolCall): CallTitle | null {
  const { tool, input } = call
  if (isRowlessTool(tool)) return null
  const path = textField(input, 'file_path') ?? textField(input, 'notebook_path')
  const shownPath = path === undefined ? '' : displayPath(path)
  switch (tool) {
    case 'Bash':
      return { name: 'Bash', summary: bashSummary(readText(field(input, 'command'))) }
    case 'PowerShell':
      return { name: 'PowerShell', summary: bashSummary(readText(field(input, 'command'))) }
    case 'Read': {
      if (path !== undefined && /\/tasks\/[^/]+\.output$/.test(path)) {
        return { name: 'Read agent output', summary: shownPath }
      }
      const pages = textField(input, 'pages')
      const name = path !== undefined && isPlanFile(path) ? 'Reading Plan' : 'Read'
      return { name, summary: pages ? `${shownPath} · pages ${pages}` : shownPath }
    }
    case 'Edit': {
      if (path !== undefined && isPlanFile(path)) return { name: 'Updated plan', summary: '' }
      // An empty old string means the edit creates the file's content
      const isCreate = readText(field(input, 'old_string'))?.text === ''
      return { name: isCreate ? 'Create' : 'Update', summary: shownPath }
    }
    case 'Write':
      if (path !== undefined && isPlanFile(path)) return { name: 'Updated plan', summary: '' }
      return { name: 'Write', summary: shownPath }
    case 'NotebookEdit': {
      const cell = textField(input, 'cell_id')
      return { name: 'Edit Notebook', summary: cell ? `${shownPath}@${cell.slice(0, 8)}` : shownPath }
    }
    case 'Grep':
    case 'Glob': {
      const pattern = textField(input, 'pattern') ?? ''
      const where = textField(input, 'path')
      const summary = `pattern: "${pattern}"${where === undefined ? '' : `, path: "${displayPath(where)}"`}`
      return { name: 'Search', summary }
    }
    case 'Agent':
    case 'Task': {
      const type = textField(input, 'subagent_type')
      const given = textField(input, 'name')
      const generic = type === undefined || type === 'general-purpose'
      const name = given ? `@${given}` : type === 'web-fetch' ? 'Fetch' : generic ? 'Agent' : type
      const tag = agentModels(call.output)
      return {
        name,
        summary: collapseSpace(textField(input, 'description') ?? ''),
        ...(tag === undefined ? {} : { tag }),
      }
    }
    case 'Skill':
      return { name: 'Skill', summary: textField(input, 'skill') ?? '' }
    case 'TaskOutput':
      // The row stays hidden while the task still works
      return call.isRunning ? null : { name: 'Task Output', summary: textField(input, 'task_id') ?? '' }
    case 'TaskStop':
      return { name: 'Stop Task', summary: '' }
    case 'WebFetch':
      return { name: 'Fetch', summary: textField(input, 'url') ?? '' }
    case 'WebSearch':
      return { name: 'Web Search', summary: `"${textField(input, 'query') ?? ''}"` }
    case 'EnterWorktree':
      return {
        name: field(input, 'path') === undefined ? 'Creating worktree' : 'Entering worktree',
        summary: '',
      }
    case 'ExitWorktree':
      return {
        name: textField(input, 'action') === 'remove' ? 'Cleaning up worktree' : 'Exiting worktree',
        summary: '',
      }
    case 'Monitor': {
      const text = collapseSpace(textField(input, 'description') ?? '')
      return { name: 'Monitor', summary: text.length > VALUE_CHARS ? `${text.slice(0, VALUE_CHARS)}…` : text }
    }
    case 'LSP':
      return { name: 'LSP', summary: '' }
    default: {
      const mcp = parseMcpTool(tool)
      // Fallback for a tool the terminal names no title for: nothing silently disappears
      if (!mcp) return { name: tool, summary: keyValueSummary(input) }
      return { name: collapseSpace(`${mcp.server} - ${mcp.name} (MCP)`), summary: keyValueSummary(input) }
    }
  }
}

/**
 * The timeout of a call, for the `(timeout 2m)` notes.
 *
 * @param call - A call.
 * @returns Milliseconds; undefined when the input sets none.
 */
export function callTimeout(call: ToolCall): number | undefined {
  return numberField(call.input, 'timeout')
}
