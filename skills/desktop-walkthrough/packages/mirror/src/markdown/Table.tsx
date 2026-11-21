import type { Tokens } from 'marked'
import type { CSSProperties, ReactNode } from 'react'

import { useColumns } from '../terminal/columns'
import { renderInline, plainText, type MarkdownMode } from './inline'
import { layoutTable } from './tableLayout'

/** Body rows drawn before the table stops with a count of the rest. */
const MAX_BODY_ROWS = 200
/** The longest rule between rows of the vertical layout. */
const VERTICAL_RULE_MAX = 40

type Align = 'left' | 'right' | 'center' | null

/** The pieces of a line a border cell draws, which join into corners and crossings. */
type Pieces = { up?: boolean; down?: boolean; left?: boolean; right?: boolean }

/** A border cell: up to four half-lines meeting at its centre. */
function Junction({ up, down, left, right }: Pieces) {
  return (
    <div className="tb" aria-hidden>
      {up && <i className="tb-u" />}
      {down && <i className="tb-d" />}
      {left && <i className="tb-l" />}
      {right && <i className="tb-r" />}
    </div>
  )
}

/**
 * Draw a markdown table the way the terminal does.
 *
 * Why it exists: a table is the one markdown block with its own layout algorithm. When it fits the
 * page it is a box-drawing grid (header centred, a line after every row, shorter cells centred
 * vertically); when it does not, each row becomes one `Header: value` line per column. Called by the
 * block renderer for every `table` token.
 *
 * @param props.token - The `table` token from `marked`.
 * @param props.mode - The markdown rule set for the cells' inline text.
 */
export function TableBlock({ token, mode }: { token: Tokens.Table; mode: MarkdownMode }) {
  const columns = useColumns()
  const body = token.rows.slice(0, MAX_BODY_ROWS)
  const hidden = token.rows.length - body.length
  const matrix = [token.header, ...body].map((row) => row.map((cell) => plainText(cell.tokens)))
  const layout = layoutTable(matrix, columns)

  const more = hidden > 0 ? <div className="dim dim-markdown">{`… ${hidden} more rows not shown`}</div> : null

  if (layout.kind === 'vertical') {
    const ruleLength = Math.min(columns - 4, VERTICAL_RULE_MAX)
    return (
      <div className="md-vertical">
        {body.map((row, rowIndex) => (
          <div key={rowIndex}>
            {/* A rule between rows, not before the first */}
            {rowIndex > 0 && <div className="md-vertical-rule">{'─'.repeat(ruleLength)}</div>}
            {row.map((cell, index) => (
              <div key={index} style={{ paddingLeft: '2ch', textIndent: '-2ch' }}>
                <strong className="md-strong">{plainText(token.header[index]?.tokens)}:</strong>{' '}
                {renderInline(cell.tokens, mode)}
              </div>
            ))}
          </div>
        ))}
        {more}
      </div>
    )
  }

  const { widths } = layout
  // A bar column, then per table column its padded text and a bar
  const template = `1ch ${widths.map((width) => `${width + 2}ch 1ch`).join(' ')}`
  const last = widths.length - 1
  const aligns: Align[] = token.align

  /** A horizontal border row: the top edge, the line between rows, or the bottom edge. */
  const border = (position: 'top' | 'middle' | 'bottom', key: string): ReactNode[] => {
    const pieces = (edge: 'left' | 'inner' | 'right'): Pieces => ({
      up: position !== 'top',
      down: position !== 'bottom',
      left: edge !== 'left',
      right: edge !== 'right',
    })
    return [
      <Junction key={`${key}-l`} {...pieces('left')} />,
      ...widths.flatMap((_, index) => [
        <Junction key={`${key}-h${index}`} left right />,
        <Junction key={`${key}-j${index}`} {...pieces(index === last ? 'right' : 'inner')} />,
      ]),
    ]
  }

  /** A content row: text cells between vertical bars. */
  const line = (cells: Tokens.TableCell[], isHeader: boolean, key: string): ReactNode[] => [
    <Junction key={`${key}-l`} up down />,
    ...widths.flatMap((_, index) => {
      const cell = cells[index]
      const align: Align = isHeader ? 'center' : (aligns[index] ?? 'left')
      const style: CSSProperties = { textAlign: align ?? 'left', padding: '0 1ch', boxSizing: 'border-box' }
      return [
        <div key={`${key}-c${index}`} className="tcell" style={style}>
          {cell ? renderInline(cell.tokens, mode) : null}
        </div>,
        <Junction key={`${key}-b${index}`} up down />,
      ]
    }),
  ]

  return (
    <div>
      <div className="md-table" style={{ gridTemplateColumns: template, width: 'max-content' }}>
        {border('top', 'top')}
        {line(token.header, true, 'head')}
        {border(body.length === 0 ? 'bottom' : 'middle', 'head-end')}
        {body.flatMap((row, rowIndex) => [
          ...line(row, false, `r${rowIndex}`),
          ...border(rowIndex === body.length - 1 ? 'bottom' : 'middle', `r${rowIndex}-end`),
        ])}
      </div>
      {more}
    </div>
  )
}
