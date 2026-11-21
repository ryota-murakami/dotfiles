import { createContext, useContext, useLayoutEffect, useRef, useState, type ReactNode } from 'react'

/** Columns assumed when nothing can be measured (a test renderer has no layout). */
const FALLBACK_COLUMNS = 80

const ColumnsContext = createContext(FALLBACK_COLUMNS)

/**
 * How many terminal columns wide the Mirror is right now.
 *
 * Why it exists: Claude Code lays tables and lists out against the terminal's column count; the Mirror
 * is as wide as the HUD makes it, so its own width, in `ch`, plays that part. Read by the markdown
 * renderer; row components under a {@link Columns} get it.
 *
 * @returns The width of the nearest {@link Columns} in whole `ch`.
 */
export function useColumns(): number {
  return useContext(ColumnsContext)
}

/**
 * Measures its own width in columns and tells the rows under it.
 *
 * Why it exists: the page's width is only known to the browser, and it changes when the HUD resizes
 * or zooms the panel; this re-measures on each change. Rendered by {@link Transcript}.
 *
 * @param props.className - Class of the measured block.
 * @param props.children - What is drawn inside; it reads the width with {@link useColumns}.
 */
export function Columns({ className, children }: { className?: string; children: ReactNode }) {
  const blockRef = useRef<HTMLDivElement>(null)
  const probeRef = useRef<HTMLSpanElement>(null)
  const [columns, setColumns] = useState(FALLBACK_COLUMNS)

  useLayoutEffect(() => {
    const block = blockRef.current
    const probe = probeRef.current
    if (!block || !probe) return
    // The probe is exactly 1ch wide, so the ratio is the column count
    const measure = () => {
      const cell = probe.getBoundingClientRect().width
      const width = block.getBoundingClientRect().width
      if (cell > 0 && width > 0) setColumns(Math.floor(width / cell + 0.01))
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(block)
    observer.observe(probe)
    return () => observer.disconnect()
  }, [])

  return (
    <div ref={blockRef} className={className}>
      <span ref={probeRef} className="columns-probe" aria-hidden />
      <ColumnsContext.Provider value={columns}>{children}</ColumnsContext.Provider>
    </div>
  )
}
