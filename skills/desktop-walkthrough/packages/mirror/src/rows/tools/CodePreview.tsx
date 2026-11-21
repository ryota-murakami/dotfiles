/**
 * A preview of the first lines of a file or a notebook cell: coloured code with a dim line-number
 * gutter, at most ten rows, then how much it left out.
 *
 * Why it exists: a Write that creates a file shows its content this way under `Wrote N lines to …`
 * (`tools.md`, section 3.5). Called by the Write and NotebookEdit results in {@link FileResults}.
 */
import { useMemo } from 'react'

import { Dim, useColumns, wrapLines } from '../../terminal'
import { ExpandHint } from './blocks'
import { highlightLines, languageForPath } from './code'
import type { ReadText } from './data'

/** Rows a preview may take after wrapping. */
const MAX_ROWS = 10
/** Columns the result frame, the gutter margin and the right margin take from the width. */
const FRAME_COLUMNS = 12

/**
 * The preview block.
 *
 * @param props.content - The file's content, whole or clipped.
 * @param props.path - The file's path; its extension picks the colours.
 * @param props.showNumbers - False draws no gutter (a notebook cell).
 * @param props.note - A dim line after the preview (`previous content replaced, no diff shown`).
 */
export function CodePreview({
  content,
  path,
  showNumbers = true,
  note,
}: {
  content: ReadText
  path: string
  showNumbers?: boolean
  note?: string
}) {
  const columns = useColumns()
  const lines = useMemo(() => {
    const all = content.text.split('\n')
    // A closing line break does not open another line
    return all.at(-1) === '' ? all.slice(0, -1) : all
  }, [content.text])
  if (content.lines === 0 && lines.length === 0) {
    return <Dim>(No content)</Dim>
  }
  const codeWidth = Math.max(10, columns - FRAME_COLUMNS)
  // Lines are shown while they fit whole inside the row limit; the rest is counted as hidden
  let rows = 0
  let shown = 0
  for (const line of lines) {
    const needed = Math.max(1, wrapLines(line, codeWidth).length)
    if (rows + needed > MAX_ROWS) break
    rows += needed
    shown++
  }
  const visible = lines.slice(0, shown)
  const hiddenLines = Math.max(0, content.lines - shown)
  const hiddenChars = Math.max(0, content.chars - visible.reduce((sum, line) => sum + line.length + 1, 0))
  const language = languageForPath(path)
  const html = language === undefined ? undefined : highlightLines(visible, language)
  const numberWidth = String(visible.length).length
  return (
    <div className="tool-code">
      {visible.map((line, index) => (
        <div key={index} className="code-row">
          {showNumbers && (
            <span className="code-gutter dim dim-faint">{` ${String(index + 1).padStart(numberWidth)} `}</span>
          )}
          {html === undefined ? (
            <span className="code-text">{line}</span>
          ) : (
            <span className="code-text" dangerouslySetInnerHTML={{ __html: html[index] ?? '' }} />
          )}
        </div>
      ))}
      {hiddenLines > 0 && <ExpandHint hidden={hiddenLines} hiddenChars={hiddenChars} />}
      {note !== undefined && (
        <div>
          <Dim>{note}</Dim>
        </div>
      )}
    </div>
  )
}
