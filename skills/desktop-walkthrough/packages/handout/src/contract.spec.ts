import { expect, test } from 'vitest'

import {
  buildOutcomeSchema,
  DEFAULT_LIMITS,
  handoutInputSchema,
  hostReplySchema,
  hostRequestSchema,
  hostResultSchema,
  pageDataSchema,
  renderReportSchema,
} from './contract'

test('the renderer accepts the input dw writes for a two-page Record', () => {
  // Arrange
  const input = {
    v: 1,
    record: {
      name: 'csv-permissions',
      dir: '/Users/u/.config/desktop-walkthrough/walkthroughs/csv-permissions',
    },
    explainDir: '/tmp/dw-handout.abc/explain',
    template: '/Users/u/dotfiles/skills/desktop-walkthrough/explainer/page.html',
    out: '/Users/u/.config/desktop-walkthrough/walkthroughs/csv-permissions/handout.html',
    log: '/tmp/dw-handout.abc/host.log',
    limits: { pageMs: 30000, runMs: 600000 },
    pages: [
      {
        n: 1,
        title: '権限の全体像',
        section: '準備',
        markdown: '# 権限の全体像\n\n本文\n',
        built: 'pages/001.html',
      },
      {
        n: 2,
        title: 'Gate で判定する',
        section: '',
        markdown: '# Gate で判定する\n',
        built: 'pages/002.html',
      },
    ],
  }

  // Act
  const parsed = handoutInputSchema.safeParse(input)

  // Assert
  expect(parsed.success).toBe(true)
})

test('the renderer refuses input written for another protocol version', () => {
  // Arrange
  const input = {
    v: 2,
    record: { name: 'r', dir: '/r' },
    explainDir: '/tmp/e',
    template: '/t/page.html',
    out: '/r/handout.html',
    log: '/tmp/host.log',
    limits: { pageMs: 30000, runMs: 600000 },
    pages: [{ n: 1, title: 'A', section: '', markdown: '# A', built: 'pages/001.html' }],
  }

  // Act
  const parsed = handoutInputSchema.safeParse(input)

  // Assert
  expect(parsed.success).toBe(false)
})

test('an input without pages never reaches the builder (dw stops an empty Record first)', () => {
  // Arrange
  const input = {
    v: 1,
    record: { name: 'r', dir: '/r' },
    explainDir: '/tmp/e',
    template: '/t/page.html',
    out: '/r/handout.html',
    log: '/tmp/host.log',
    limits: { pageMs: 30000, runMs: 600000 },
    pages: [],
  }

  // Act
  const parsed = handoutInputSchema.safeParse(input)

  // Assert
  expect(parsed.success).toBe(false)
})

test('a real export waits 30 s for a page and 10 min for the whole run', () => {
  // Arrange
  const expected = { pageMs: 30000, runMs: 600000 }

  // Act
  const limits = DEFAULT_LIMITS

  // Assert
  expect(limits).toEqual(expected)
})

test('a page built for the HUD carries no mode, so it renders exactly as before', () => {
  // Arrange
  const hudData = { n: 3, title: '解説 3', step: '仕組み', markdown: '# 解説 3' }

  // Act
  const parsed = pageDataSchema.parse(hudData)

  // Assert
  expect(parsed.mode).toBeUndefined()
})

test('the HUD render report (no library list) and the Handout one (with it) are both accepted', () => {
  // Arrange
  const hudReport = { type: 'rendered', page: 4, diagrams: 1, errors: [] }
  const handoutReport = {
    type: 'rendered',
    page: 4,
    diagrams: 1,
    errors: [],
    libs: ['marked', 'highlight', 'highlight-http', 'mermaid', 'purify'],
  }

  // Act
  const hudParsed = renderReportSchema.safeParse(hudReport)
  const handoutParsed = renderReportSchema.safeParse(handoutReport)

  // Assert
  expect(hudParsed.success).toBe(true)
  expect(handoutParsed.success).toBe(true)
})

test('a render report naming a library the page does not load is refused', () => {
  // Arrange
  const report = { type: 'rendered', page: 4, diagrams: 0, errors: [], libs: ['jquery'] }

  // Act
  const parsed = renderReportSchema.safeParse(report)

  // Assert
  expect(parsed.success).toBe(false)
})

test('the builder can ask the host to render a page, read a file and verify the finished Handout', () => {
  // Arrange
  const requests = [
    { type: 'render', page: 1, probe: 'return document.title' },
    { type: 'read', path: '/r/pages/shot.png' },
    { type: 'verify', html: '<!doctype html><html></html>', probe: 'return location.hash' },
  ]

  // Act
  const parsed = requests.map((request) => hostRequestSchema.safeParse(request).success)

  // Assert
  expect(parsed).toEqual([true, true, true])
})

test('the builder refuses a host reply of a kind the contract does not have', () => {
  // Arrange
  const reply = { type: 'published', path: '/r/handout.html' }

  // Act
  const parsed = hostReplySchema.safeParse(reply)

  // Assert
  expect(parsed.success).toBe(false)
})

test('a failed build names at least one coded reason', () => {
  // Arrange
  const withoutReason = { ok: false, diagnostics: [] }
  const withReason = {
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_SECRET',
        message: 'a secret shape in the page source',
        page: 2,
        line: 14,
        pattern: 'github-token',
      },
    ],
  }

  // Act
  const withoutParsed = buildOutcomeSchema.safeParse(withoutReason)
  const withParsed = buildOutcomeSchema.safeParse(withReason)

  // Assert
  expect(withoutParsed.success).toBe(false)
  expect(withParsed.success).toBe(true)
})

test('a failure code outside the HANDOUT_* table is refused, so SKILL.md can list every code', () => {
  // Arrange
  const result = {
    v: 1,
    ok: false,
    diagnostics: [{ code: 'HANDOUT_TIMEOUT', message: 'page 3 did not report within 30 s' }],
    log: '/tmp/host.log',
  }

  // Act
  const parsed = hostResultSchema.safeParse(result)

  // Assert
  expect(parsed.success).toBe(false)
})

test('dw can print the summary line from a successful result', () => {
  // Arrange
  const result = {
    v: 1,
    ok: true,
    path: '/r/handout.html',
    pages: 12,
    diagrams: 7,
    warnings: [{ message: 'HUD wording outside a hud-only block: 「パネル」', page: 3, line: 8 }],
  }

  // Act
  const parsed = hostResultSchema.parse(result)

  // Assert
  expect(parsed).toEqual(result)
})
