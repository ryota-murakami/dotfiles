/**
 * The names the assembled Handout, its controller and the verify probe agree on.
 *
 * Why it exists: the builder writes the Handout's markup, the controller (a separate script inside
 * that file) drives it, and the verify probe checks it in the reopened file. A renamed id in one of
 * the three would pass each one's own specs and break the file the colleague receives.
 */
export const HANDOUT_DOM = {
  /** Class of every page: `<article class="page" id="page-3" data-n="3">`. */
  pageClass: 'page',
  /** Prefix of a page's id; the number follows. */
  pageIdPrefix: 'page-',
  /** Class of a page's section line, above its content. */
  sectionClass: 'section',
  /** Class on `<body>`: page.html's Handout-mode rules (pinned diagram text) apply under it. */
  bodyClass: 'handout',
  /** Id of the `<script type="application/json">` holding the table of contents: `[{n, title, section}]`. */
  tocDataId: 'handout-toc',
  /** Attribute the controller sets on `<html>` once it took over the page. */
  readyAttribute: 'data-handout-ready',
  /** Id of the header's `N/M`. */
  pageNumberId: 'pageno',
} as const

/** One entry of the table of contents the builder embeds and the controller reads. */
export interface TocEntry {
  n: number
  title: string
  section: string
}
