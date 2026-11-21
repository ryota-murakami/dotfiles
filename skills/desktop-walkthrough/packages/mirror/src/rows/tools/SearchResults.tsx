/**
 * The results of the search and web tools, the MCP tools and the fallback for tools the terminal has
 * no wording for (`tools.md`, sections 3.6 and 3.8).
 *
 * Why it exists: each of these says what it found in one short row, and an MCP result is drawn like
 * Bash output. Called by {@link ToolResultView} for a finished Grep, Glob, WebFetch, WebSearch, MCP or
 * unknown tool call.
 */
import type { ToolCall } from '@dw/protocol'

import { Dim, Gutter, useColumns } from '../../terminal'
import { ClampedText, Strong } from './blocks'
import { field, isRecord, numberField, readList, readText, textField, type ReadText } from './data'
import { formatDuration } from '../duration'
import { formatSize, nounFor } from './format'

/** Columns the output block loses to the result frame. */
const FRAME_COLUMNS = 10
/** Tokens above which an MCP response gets a warning row. */
const LARGE_MCP_TOKENS = 10_000

/**
 * Grep's and Glob's row: `Found N files`, `Found N lines` or `Found N matches across M files`.
 *
 * @param props.call - The call with its `output` (`mode`, `numFiles`, `numLines`, `numMatches`, `filenames`).
 */
export function SearchResult({ call }: { call: ToolCall }) {
  const output = call.output
  const files = numberField(output, 'numFiles') ?? readList(field(output, 'filenames')).items.length
  const mode =
    call.tool === 'Glob'
      ? 'files_with_matches'
      : (textField(output, 'mode') ?? textField(call.input, 'output_mode'))
  let count: number
  let summary
  if (mode === 'content') {
    count = numberField(output, 'numLines') ?? readText(field(output, 'content'))?.lines ?? 0
    summary = (
      <>
        Found <Strong>{count}</Strong> {nounFor(count, 'line')}
      </>
    )
  } else if (mode === 'count') {
    count = numberField(output, 'numMatches') ?? 0
    summary = (
      <>
        Found <Strong>{count}</Strong> {nounFor(count, 'match', 'matches')} across <Strong>{files}</Strong>{' '}
        {nounFor(files, 'file')}
      </>
    )
  } else {
    count = files
    summary = (
      <>
        Found <Strong>{count}</Strong> {nounFor(count, 'file')}
      </>
    )
  }
  return (
    <Gutter>
      <div>
        {summary}
        {count > 0 && <Dim>{' (ctrl+o to expand)'}</Dim>}
      </div>
    </Gutter>
  )
}

/**
 * WebFetch's row: `Received 12KB (200 OK)`.
 *
 * @param props.call - The call with its `output` (`bytes`, `code`, `codeText`).
 */
export function WebFetchResult({ call }: { call: ToolCall }) {
  const bytes = numberField(call.output, 'bytes') ?? 0
  const code = numberField(call.output, 'code')
  const codeText = textField(call.output, 'codeText')
  const status = code === undefined ? '' : ` (${code}${codeText ? ` ${codeText}` : ''})`
  return (
    <Gutter>
      Received <Strong>{formatSize(bytes)}</Strong>
      {status}
    </Gutter>
  )
}

/**
 * WebSearch's row: `Did 2 searches in 5s`.
 *
 * @param props.call - The call with its `output` (`searchCount`, `results`, `durationSeconds`).
 */
export function WebSearchResult({ call }: { call: ToolCall }) {
  const results = readList(field(call.output, 'results')).items
  const searches =
    numberField(call.output, 'searchCount') ?? results.filter((item) => typeof item !== 'string').length
  const seconds = numberField(call.output, 'durationSeconds') ?? 0
  return (
    <Gutter>
      Did {searches === 0 ? 'no' : <Strong>{searches}</Strong>} {nounFor(searches, 'search', 'searches')}
      {seconds >= 1 && ` in ${formatDuration(seconds * 1000)}`}
    </Gutter>
  )
}

/** The text of an MCP result: a string, the text blocks of a content list, or nothing. */
function mcpContent(output: unknown): { text: ReadText | undefined; hasImage: boolean } {
  const direct = readText(output)
  if (direct) return { text: direct, hasImage: false }
  const blocks = readList(Array.isArray(output) ? output : field(output, 'content')).items
  let hasImage = false
  const parts: string[] = []
  let chars = 0
  let isClipped = false
  for (const block of blocks) {
    if (isRecord(block) && block['type'] === 'image') {
      hasImage = true
      continue
    }
    const text = readText(isRecord(block) ? block['text'] : block)
    if (!text) continue
    parts.push(text.text)
    chars += text.chars
    isClipped ||= text.isClipped
  }
  if (parts.length === 0) return { text: undefined, hasImage }
  const joined = parts.join('\n')
  return {
    text: {
      text: joined,
      lines: joined.split('\n').length,
      chars: Math.max(chars, joined.length),
      isClipped,
    },
    hasImage,
  }
}

/**
 * An MCP tool's result: its text drawn like Bash output, `[Image]` for an image, a warning when large.
 *
 * @param props.call - The call with its `output`.
 */
export function McpResult({ call }: { call: ToolCall }) {
  const width = Math.max(useColumns() - FRAME_COLUMNS, 10)
  const { text, hasImage } = mcpContent(call.output)
  const tokens = (text?.chars ?? 0) / 4
  return (
    <Gutter>
      <div>
        {tokens > LARGE_MCP_TOKENS && (
          <div className="tool-warning">{`⚠ Large MCP response (~${(tokens / 1000).toFixed(1)}k tokens) · can fill context quickly`}</div>
        )}
        {hasImage && <div>[Image]</div>}
        {text && text.text.trim() !== '' ? (
          <ClampedText text={text} width={width} limit={3} isLenient />
        ) : (
          !hasImage && <div>(No content)</div>
        )}
      </div>
    </Gutter>
  )
}

/**
 * The result of a tool the Mirror has no wording for: its text when it has a plain one, else nothing.
 *
 * @param props.call - The call with its `output`.
 */
export function GenericResult({ call }: { call: ToolCall }) {
  const width = Math.max(useColumns() - FRAME_COLUMNS, 10)
  const output = call.output
  // A plain text, or the usual text-carrying fields of a result object
  const text =
    readText(output) ??
    readText(field(output, 'message')) ??
    readText(field(output, 'result')) ??
    readText(field(output, 'output'))
  if (!text || text.text.trim() === '') return null
  return (
    <Gutter>
      <div>
        <ClampedText text={text} width={width} limit={3} isLenient />
      </div>
    </Gutter>
  )
}
