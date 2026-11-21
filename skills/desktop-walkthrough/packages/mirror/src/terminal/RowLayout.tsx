import { createContext, useContext, type CSSProperties, type ReactNode } from 'react'

/** The glyphs Claude Code shares between rows (messages.md, section 1.3). */
export const GLYPH = {
  /** The row bullet (`⏺` on macOS). */
  bullet: '⏺',
  /** The prompt pointer. */
  pointer: '❯',
  /** The marker of a message from another agent. */
  pointerSmall: '›',
  /** The result gutter's elbow. */
  gutter: '⎿',
  /** The turn-duration and compaction marker. */
  notice: '✻',
  /** The thinking marker. */
  thinking: '∴',
  /** The blockquote bar. */
  quoteBar: '▎',
  tick: '✔',
  ellipsis: '…',
} as const

/** How a faint text is coloured: the three things Claude Code calls dim. */
export type DimTone =
  /** `dimColor` on a text node: the explicit grey `inactive`. Notes, gutters, hints. */
  | 'inactive'
  /** SGR 2 over the default foreground: tool and command output, `… +N lines`. */
  | 'faint'
  /** Chalk dim inside markdown: a code fence's language label. */
  | 'markdown'

/**
 * Dim text.
 *
 * Why it exists: Claude Code has three dims that are coloured differently (messages.md, section 1.2);
 * one class each lets a row pick the right one by name. Used by every row that draws a note, a hint or
 * a gutter, and by the tool rows and the spinner line later.
 *
 * @param props.tone - Which dim; `inactive` when omitted.
 */
export function Dim({ tone = 'inactive', children }: { tone?: DimTone; children: ReactNode }) {
  return <span className={`dim dim-${tone}`}>{children}</span>
}

/** Whether the content is already inside a `⎿` gutter: a nested gutter draws no second elbow. */
const InsideGutterContext = createContext(false)

/**
 * The result gutter `⎿` that hangs a result line under its row.
 *
 * Why it exists: results of tools and slash commands sit under their row, five columns in, with the
 * elbow in the first (two spaces, `⎿`, a space and a no-break space, all dim). Continuation lines of
 * the content stay under its first line. Used by {@link CommandOutputRow}, and by the tool rows.
 *
 * @param props.children - The result's content; it wraps in the room right of the gutter.
 */
export function Gutter({ children }: { children: ReactNode }) {
  // Inside another gutter the content is drawn bare: the inner result shares the outer elbow
  if (useContext(InsideGutterContext)) return <>{children}</>
  return (
    <div className="gutter-row">
      <span className="gutter dim dim-inactive" aria-hidden>
        {'  ' + GLYPH.gutter + '  '}
      </span>
      <div className="gutter-content">
        <InsideGutterContext.Provider value>{children}</InsideGutterContext.Provider>
      </div>
    </div>
  )
}

/** What {@link RowLayout} takes. */
export type RowLayoutProps = {
  /** The marker cell's glyph; `false` draws no cell at all (the content then starts at the edge). */
  marker?: string | false
  /** The marker's colour: a CSS colour, for example `themeColor('success')`; the default foreground when omitted. */
  markerColor?: string
  /** Screen-reader label of the marker (`claude:`). */
  markerLabel?: string
  /** One blank row above, as every message row has; false for a row that hangs under the previous one. */
  addMargin?: boolean
  /** Extra class for the row. */
  className?: string
  style?: CSSProperties
  children: ReactNode
}

/**
 * The glyph row: a two-column marker cell, then the content, which wraps in the room that is left.
 *
 * Why it exists: nearly every row of the terminal has this shape (`ki` in the reference): a bullet or
 * a pointer in a box two columns wide, with the content's continuation lines aligned under its first
 * line, and a blank row above. Every row of the Mirror, and the later tool rows, are drawn through it.
 *
 * @param props - See {@link RowLayoutProps}.
 */
export function RowLayout({
  marker = GLYPH.bullet,
  markerColor,
  markerLabel,
  addMargin = true,
  className,
  style,
  children,
}: RowLayoutProps) {
  const classes = ['row', addMargin ? 'row-margin' : undefined, className].filter(Boolean).join(' ')
  return (
    <div className={classes} style={style}>
      {marker !== false && (
        <span
          className="marker"
          style={markerColor ? { color: markerColor } : undefined}
          aria-label={markerLabel}
        >
          {marker}
        </span>
      )}
      <div className="row-content">{children}</div>
    </div>
  )
}
