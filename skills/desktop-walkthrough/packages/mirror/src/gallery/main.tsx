import { galleryFixtures, turnInProgress } from '@dw/protocol/fixtures'
import { toolGalleryFixtures } from '@dw/protocol/fixtures-tools'
import type { Row } from '@dw/protocol'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import { LiveGallery } from '../live/LiveGallery'
import { Transcript } from '../rows/Transcript'
import '../styles.css'
import './gallery.css'

/** The widths, in columns, every fixture is drawn at: a wide panel and a narrow one. */
const WIDTHS = [110, 60] as const

/** One fixture's Rows at every width, side by side. */
function Section({ title, note, rows }: { title: string; note: string; rows: readonly Row[] }) {
  return (
    <section className="gallery-section" id={title.toLowerCase().replaceAll(/[^a-z0-9]+/g, '-')}>
      <h2 className="gallery-title">{title}</h2>
      <p className="gallery-note">{note}</p>
      <div className="gallery-frames">
        {WIDTHS.map((columns) => (
          <div key={columns}>
            <div className="gallery-caption">{columns} columns</div>
            <div className="gallery-frame" style={{ width: `${columns}ch` }} data-columns={columns}>
              <Transcript rows={rows} />
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}

/**
 * The development gallery: every fixture drawn at two widths, to check the look in a browser against
 * the terminal. Not part of the built page; `pnpm --filter @dw/mirror dev` serves it at `/gallery.html`.
 * `?size=16px` sets the font size the way the HUD's zoom does.
 */
function Gallery() {
  const sections = [
    { title: 'A turn in progress', note: 'Tool rows are placeholders for now.', rows: turnInProgress.rows },
    ...galleryFixtures,
    ...toolGalleryFixtures,
  ]
  return (
    <>
      {sections.map((section) => (
        <Section key={section.title} {...section} />
      ))}
      <LiveGallery />
    </>
  )
}

const size = new URLSearchParams(location.search).get('size')
if (size) document.documentElement.style.setProperty('--mirror-font-size', size)

const root = document.getElementById('root')
if (root) {
  createRoot(root).render(
    <StrictMode>
      <Gallery />
    </StrictMode>,
  )
}
