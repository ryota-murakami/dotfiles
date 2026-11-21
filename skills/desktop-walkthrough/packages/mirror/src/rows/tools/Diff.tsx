/**
 * The diff view of an Edit or a Write result: line numbers, added and removed rows with whole-row
 * backgrounds, word-level highlights, context and the ends where the Bridge cut the patch.
 *
 * Why it exists: `tools.md` (section 3.5) describes how the terminal draws a structured patch; this is
 * that drawing. Called by the Edit and Write results in {@link FileResults}.
 */
import { Dim } from '../../terminal'
import { field, isRecord, numberField, readList, readText } from './data'
import { diffWords, type WordSpan } from './wordDiff'

/** One row of the diff. */
type DiffRow = {
  kind: 'add' | 'remove' | 'context'
  number: number
  code: string
  /** The row's words with the changed ones marked; undefined draws the row plain. */
  spans?: WordSpan[]
}

/** A hunk: rows around one change, and how many of its lines the Bridge left out. */
type Hunk = { rows: DiffRow[]; lostLines: number }

/** A token longer than this is cut, and the cut is noted. */
const MAX_TOKEN_CHARS = 200

/**
 * Read a structured patch into rows.
 *
 * @param patch - The result's `structuredPatch`: hunks with `oldStart`, `newStart` and `lines` that begin with `+`, `-` or a space.
 * @returns The hunks, and how many hunks the Bridge left out after them.
 */
function parsePatch(patch: unknown): { hunks: Hunk[]; lostHunks: number } {
  const { items, more } = readList(patch)
  const hunks: Hunk[] = []
  for (const item of items) {
    if (!isRecord(item)) continue
    let oldLine = numberField(item, 'oldStart') ?? 1
    let newLine = numberField(item, 'newStart') ?? 1
    const { items: lines, more: lostLines } = readList(field(item, 'lines'))
    const rows: DiffRow[] = []
    for (const line of lines) {
      const text = readText(line)?.text
      if (text === undefined || text.startsWith('\\')) continue
      // Leading tabs are drawn as two spaces
      const code = text.slice(1).replace(/^\t+/, (tabs) => '  '.repeat(tabs.length))
      const marker = text[0]
      if (marker === '+') rows.push({ kind: 'add', number: newLine++, code })
      else if (marker === '-') rows.push({ kind: 'remove', number: oldLine++, code })
      else {
        rows.push({ kind: 'context', number: newLine++, code })
        oldLine++
      }
    }
    pairWords(rows)
    hunks.push({ rows, lostLines })
  }
  return { hunks, lostHunks: more }
}

/** Pair each run of removed rows with the run of added rows after it, in order, and mark their changed words. */
function pairWords(rows: DiffRow[]): void {
  let index = 0
  while (index < rows.length) {
    if (rows[index]?.kind !== 'remove') {
      index++
      continue
    }
    const removedStart = index
    while (rows[index]?.kind === 'remove') index++
    const addedStart = index
    while (rows[index]?.kind === 'add') index++
    const pairs = Math.min(addedStart - removedStart, index - addedStart)
    for (let offset = 0; offset < pairs; offset++) {
      const removed = rows[removedStart + offset]
      const added = rows[addedStart + offset]
      if (!removed || !added) continue
      const words = diffWords(removed.code, added.code)
      if (words) {
        removed.spans = words.removed
        added.spans = words.added
      }
    }
  }
}

/**
 * How many lines a patch adds and removes.
 *
 * @param patch - The result's `structuredPatch`.
 * @returns The counts of lines that start with `+` and `-`.
 */
export function countChanges(patch: unknown): { added: number; removed: number } {
  let added = 0
  let removed = 0
  for (const hunk of readList(patch).items) {
    for (const line of readList(field(hunk, 'lines')).items) {
      const text = readText(line)?.text
      if (text?.startsWith('+')) added++
      else if (text?.startsWith('-')) removed++
    }
  }
  return { added, removed }
}

/** The code of a row; a token longer than the cap is cut and followed by a dim note of what was hidden. */
function RowCode({ row }: { row: DiffRow }) {
  const parts = row.code.split(/(\s+)/)
  const hidden = parts.reduce((sum, part) => sum + Math.max(0, part.length - MAX_TOKEN_CHARS), 0)
  if (hidden > 0) {
    return (
      <>
        {parts.map((part) => part.slice(0, MAX_TOKEN_CHARS)).join('')}
        <Dim>{` … +${hidden} chars`}</Dim>
      </>
    )
  }
  if (!row.spans) return <>{row.code}</>
  const wordClass = row.kind === 'add' ? 'diff-word-add' : 'diff-word-remove'
  return (
    <>
      {row.spans.map((span, index) =>
        span.isChanged ? (
          <span key={index} className={wordClass}>
            {span.text}
          </span>
        ) : (
          span.text
        ),
      )}
    </>
  )
}

/**
 * A structured patch as the terminal's diff.
 *
 * @param props.patch - The result's `structuredPatch`, with the Bridge's cut forms.
 * @param props.isDimmed - True for an edit that was never applied: the backgrounds and the text are dimmed.
 */
export function DiffView({ patch, isDimmed = false }: { patch: unknown; isDimmed?: boolean }) {
  const { hunks, lostHunks } = parsePatch(patch)
  return (
    <div className={isDimmed ? 'diff diff-dimmed' : 'diff'}>
      {hunks.map((hunk, hunkIndex) => {
        const widest = Math.max(1, ...hunk.rows.map((row) => String(row.number).length))
        return (
          <div key={hunkIndex}>
            {/* Hunks are told apart by a dim ellipsis row */}
            {hunkIndex > 0 && (
              <div>
                <Dim>...</Dim>
              </div>
            )}
            {hunk.rows.map((row, rowIndex) => (
              <div key={rowIndex} className={`diff-row diff-${row.kind}`}>
                <span className={row.kind === 'context' ? 'diff-gutter diff-gutter-context' : 'diff-gutter'}>
                  {`${String(row.number).padStart(widest)} `}
                </span>
                <span className="diff-marker">
                  {row.kind === 'add' ? '+' : row.kind === 'remove' ? '-' : ' '}
                </span>
                <span className="diff-code">
                  <RowCode row={row} />
                </span>
              </div>
            ))}
            {hunk.lostLines > 0 && (
              <div>
                <Dim>{`… +${hunk.lostLines} ${hunk.lostLines === 1 ? 'line' : 'lines'} (ctrl+o to expand)`}</Dim>
              </div>
            )}
          </div>
        )
      })}
      {lostHunks > 0 && (
        <div>
          <Dim>{`… +${lostHunks} ${lostHunks === 1 ? 'hunk' : 'hunks'} (ctrl+o to expand)`}</Dim>
        </div>
      )}
    </div>
  )
}
