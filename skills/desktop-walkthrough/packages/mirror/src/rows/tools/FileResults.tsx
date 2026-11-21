/**
 * The results of the file tools: Read's one-line summary, Edit's and Write's diff, a created file's
 * preview and a notebook cell (`tools.md`, sections 3.4 and 3.5).
 *
 * Why it exists: these tools are the bulk of a coding Session's calls and each reports in its own
 * words. Called by {@link ToolResultView} for a finished Read, Edit, Write or NotebookEdit call.
 */
import type { ToolCall } from '@dw/protocol'

import { Markdown } from '../../markdown/Markdown'
import { Dim, Gutter } from '../../terminal'
import { Strong } from './blocks'
import { CodePreview } from './CodePreview'
import { field, readList, readText, textField, numberField } from './data'
import { countChanges, DiffView } from './Diff'
import { displayPath, formatSize, nounFor } from './format'

/** Whether a path is a Claude Code plan file, whose edits show only a hint. */
function isPlanPath(path: string | undefined): boolean {
  return path !== undefined && /\/\.claude\/plans\/[^/]+\.md$/.test(path)
}

/**
 * Read's one row: how many lines, or what kind of thing it read.
 *
 * @param props.call - The Read call with its `output` (`type`, `file`).
 */
export function ReadResult({ call }: { call: ToolCall }) {
  const type = textField(call.output, 'type')
  const file = field(call.output, 'file')
  if (type === 'image') {
    return <Gutter>{`Read image (${formatSize(numberField(file, 'originalSize') ?? 0)})`}</Gutter>
  }
  if (type === 'pdf') {
    return <Gutter>{`Read PDF (${formatSize(numberField(file, 'originalSize') ?? 0)})`}</Gutter>
  }
  if (type === 'parts') {
    const pages = numberField(file, 'count') ?? 0
    return (
      <Gutter>
        Read <Strong>{pages}</Strong> {nounFor(pages, 'page')} (
        {formatSize(numberField(file, 'originalSize') ?? 0)})
      </Gutter>
    )
  }
  if (type === 'notebook') {
    const { items, more } = readList(field(file, 'cells'))
    const cells = items.length + more
    if (cells === 0) {
      return (
        <Gutter>
          <div className="tool-error">No cells found in notebook</div>
        </Gutter>
      )
    }
    return (
      <Gutter>
        Read <Strong>{cells}</Strong> cells
      </Gutter>
    )
  }
  // Text: the returned line count; the content itself is not drawn
  const content = readText(field(file, 'content'))
  const lines = numberField(file, 'numLines') ?? content?.lines ?? 0
  return (
    <Gutter>
      Read <Strong>{lines}</Strong> {nounFor(lines, 'line')}
    </Gutter>
  )
}

/** The `Added N lines, removed M lines` row of a patch. */
function ChangeSummary({ added, removed }: { added: number; removed: number }) {
  return (
    <div>
      {added > 0 && (
        <>
          Added <Strong>{added}</Strong> {nounFor(added, 'line')}
        </>
      )}
      {added > 0 && removed > 0 && ', '}
      {removed > 0 && (
        <>
          {added > 0 ? 'removed' : 'Removed'} <Strong>{removed}</Strong> {nounFor(removed, 'line')}
        </>
      )}
    </div>
  )
}

/**
 * The summary row and the diff of a patch.
 *
 * @param props.patch - The result's `structuredPatch`.
 */
function PatchResult({ patch }: { patch: unknown }) {
  const { added, removed } = countChanges(patch)
  return (
    <Gutter>
      <ChangeSummary added={added} removed={removed} />
      <DiffView patch={patch} />
    </Gutter>
  )
}

/**
 * Edit's result: how many lines were added and removed, and the diff.
 *
 * @param props.call - The Edit call with its `output` (`structuredPatch`).
 */
export function EditResult({ call }: { call: ToolCall }) {
  if (isPlanPath(textField(call.input, 'file_path'))) {
    return (
      <Gutter>
        <Dim>/plan to preview</Dim>
      </Gutter>
    )
  }
  return <PatchResult patch={field(call.output, 'structuredPatch')} />
}

/**
 * Write's result: `Wrote N lines to <path>` and a preview for a new file; the diff for an existing one.
 *
 * @param props.call - The Write call with its `output` (`type`, `filePath`, `content`, `structuredPatch`).
 */
export function WriteResult({ call }: { call: ToolCall }) {
  const path = textField(call.output, 'filePath') ?? textField(call.input, 'file_path') ?? ''
  if (isPlanPath(path)) {
    return (
      <Gutter>
        <Dim>/plan to preview</Dim>
      </Gutter>
    )
  }
  const patch = field(call.output, 'structuredPatch')
  const hasPatch = readList(patch).items.length > 0
  // An update with a diff reads like an edit
  if (textField(call.output, 'type') === 'update' && hasPatch) return <PatchResult patch={patch} />
  // The bridge may leave the output's content out: the call's own input has the same text
  const outputContent = readText(field(call.output, 'content'))
  const content =
    outputContent && outputContent.chars > 0
      ? outputContent
      : (readText(field(call.input, 'content')) ?? outputContent)
  const isUpdate = textField(call.output, 'type') === 'update'
  if (!content) return null
  return (
    <Gutter>
      <div>
        Wrote <Strong>{content.lines}</Strong> {nounFor(content.lines, 'line')} to{' '}
        <Strong>{displayPath(path)}</Strong>
      </div>
      <CodePreview
        content={content}
        path={path}
        {...(isUpdate ? { note: 'previous content replaced, no diff shown' } : {})}
      />
    </Gutter>
  )
}

/**
 * NotebookEdit's result: the cell that changed and its new source.
 *
 * @param props.call - The NotebookEdit call with its `output` (`cell_id`, `new_source`, `cell_type`, `error`).
 */
export function NotebookResult({ call }: { call: ToolCall }) {
  const error = textField(call.output, 'error')
  if (error !== undefined && error !== '') {
    return (
      <Gutter>
        <div className="tool-error">{error}</div>
      </Gutter>
    )
  }
  const cell = textField(call.output, 'cell_id') ?? textField(call.input, 'cell_id')
  const source = readText(field(call.output, 'new_source'))
  const isCode = textField(call.output, 'cell_type') !== 'markdown'
  return (
    <Gutter>
      <div>Updated cell {cell !== undefined && <Strong>{cell}</Strong>}:</div>
      {source && source.text !== '' && (
        <div className="tool-indent">
          {isCode ? (
            <CodePreview content={source} path="cell.py" showNumbers={false} />
          ) : (
            <Markdown source={source.text} />
          )}
        </div>
      )}
    </Gutter>
  )
}

/**
 * The dim line of an edit that never applied: `Interrupted update to <path>`.
 *
 * @param props.verb - `update`, `write` or `edit`.
 * @param props.path - The file.
 * @param props.cell - The notebook cell, for a notebook edit.
 */
export function InterruptedEdit({ verb, path, cell }: { verb: string; path: string; cell?: string }) {
  return (
    <Gutter>
      <Dim>
        Interrupted {verb} to <Strong>{displayPath(path)}</Strong>
        {cell === undefined ? '' : ` at cell ${cell}`}
      </Dim>
    </Gutter>
  )
}
