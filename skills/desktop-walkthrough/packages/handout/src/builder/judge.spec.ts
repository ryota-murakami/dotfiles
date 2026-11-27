import { expect, test } from 'vitest'

import { judgeRenderedPage, missingLibraries } from './judge'

const page = {
  n: 2,
  title: '判定の仕組み',
  section: '仕組み',
  markdown: [
    '# 判定の仕組み',
    '',
    '```mermaid',
    'flowchart LR',
    '  A --> B',
    '```',
    '',
    '```mermaid',
    'flowchart TB',
    '```',
  ].join('\n'),
  built: 'pages/002.html',
}
const fitting = { text: '書き出す', width: 70, height: 24, contentWidth: 70, contentHeight: 24 }
const allLibraries = ['marked', 'highlight', 'highlight-http', 'mermaid', 'purify'] as const

test('a diagram that failed to render names its page, number and fence line', () => {
  // Arrange
  const report = {
    type: 'rendered' as const,
    page: 2,
    diagrams: 2,
    errors: ['diagram 2: Parse error on line 1:\nflowchart TB\n----^'],
    libs: [...allLibraries],
  }
  const measurement = {
    html: '',
    diagrams: [
      { id: 'p2-d1', labels: [fitting] },
      { id: '', labels: [] },
    ],
  }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_DIAGRAM',
      message: 'page 2:8: diagram 2 did not render: Parse error on line 1: flowchart TB ----^',
      page: 2,
      diagram: 2,
      line: 8,
    },
  ])
})

test('a label wider than its node stops the export, quoting the label and both sizes', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 1, errors: [], libs: [...allLibraries] }
  const measurement = {
    html: '',
    diagrams: [
      {
        id: 'p2-d1',
        labels: [
          { text: '利用者が書き出しを押す', width: 120, height: 24, contentWidth: 168.4, contentHeight: 24 },
        ],
      },
    ],
  }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_OVERFLOW',
      message:
        'page 2:3: diagram 1: the label 「利用者が書き出しを押す」 needs 168×24 px in a 120×24 px box: a style on the page changes diagram text, or a font loaded late; remove the style or shorten the label',
      page: 2,
      diagram: 1,
      line: 3,
    },
  ])
})

test('a label that wrapped to more lines than its box holds stops the export', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 1, errors: [], libs: [...allLibraries] }
  const measurement = {
    html: '',
    diagrams: [
      {
        id: 'p2-d1',
        labels: [{ text: '長い説明', width: 120, height: 24, contentWidth: 120, contentHeight: 48 }],
      },
    ],
  }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['HANDOUT_OVERFLOW'])
})

test('a label off by sub-pixel rounding still fits', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 1, errors: [], libs: [...allLibraries] }
  const measurement = {
    html: '',
    diagrams: [
      {
        id: 'p2-d1',
        labels: [{ text: '書き出す', width: 70, height: 24, contentWidth: 71.5, contentHeight: 25.5 }],
      },
    ],
  }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a diagram whose labels have no size fails closed instead of passing the overflow check on nothing', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 1, errors: [], libs: [...allLibraries] }
  const measurement = {
    html: '',
    diagrams: [
      { id: 'p2-d1', labels: [{ text: '書き出す', width: 0, height: 0, contentWidth: 0, contentHeight: 0 }] },
    ],
  }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_DIAGRAM',
      message: 'page 2:3: diagram 1 has no label with a size: nothing was laid out to check',
      page: 2,
      diagram: 1,
      line: 3,
    },
  ])
})

test('the empty label mermaid draws on an unlabelled arrow neither fails nor overflows', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 1, errors: [], libs: [...allLibraries] }
  const emptyEdgeLabel = { text: '', width: 0, height: 0, contentWidth: 12, contentHeight: 24 }
  const measurement = { html: '', diagrams: [{ id: 'p2-d1', labels: [emptyEdgeLabel, fitting] }] }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a page rendered in the HUD’s way (no library list) counts every library as missing', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 0, errors: [] }

  // Act
  const missing = missingLibraries(report)

  // Assert
  expect(missing).toEqual(['marked', 'highlight', 'highlight-http', 'mermaid', 'purify'])
})

test('an audience marker that reached the page as HTML stops the export: dw’s filter never read it', () => {
  // Arrange
  const report = {
    type: 'rendered' as const,
    page: 2,
    diagrams: 0,
    errors: ['marker: <!-- hud-only --> reached the page as HTML'],
    libs: [...allLibraries],
  }

  // Act
  const diagnostics = judgeRenderedPage(page, report, { html: '', diagrams: [] })

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_MARKER',
      message:
        'page 2: an audience marker reached the page as HTML: dw did not read it (a code fence that opens inside a list item or a quote, or a list that ends inside one, hides the markers after it); put each fence and marker at the left edge, then export again',
      page: 2,
    },
  ])
})

test('a label with text that was not laid out stops the export, even beside a label that fits', () => {
  // Arrange
  const report = { type: 'rendered' as const, page: 2, diagrams: 1, errors: [], libs: [...allLibraries] }
  const hidden = { text: '隠れた説明', width: 0, height: 0, contentWidth: 0, contentHeight: 0 }
  const measurement = { html: '', diagrams: [{ id: 'p2-d1', labels: [fitting, hidden] }] }

  // Act
  const diagnostics = judgeRenderedPage(page, report, measurement)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_DIAGRAM',
      message:
        'page 2:3: diagram 1: the label 「隠れた説明」 was not laid out (it has no size): a style on the page hides diagram text, or the diagram did not finish drawing; remove the style and export again',
      page: 2,
      diagram: 1,
      line: 3,
    },
  ])
})
