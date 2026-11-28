// @vitest-environment jsdom
import { expect, test } from 'vitest'

import type { HandoutInput, HostReply, HostRequest, RenderReport } from '../contract'
import { buildHandout } from './build'
import type { PageMeasurement } from './probes'

// Fake credentials are assembled at run time so secret scanners do not flag this public file.
const GITHUB_TOKEN = ['ghp', 'y'.repeat(36)].join('_')
const allLibraries: RenderReport['libs'] = ['marked', 'highlight', 'highlight-http', 'mermaid', 'purify']

/** Base64 of a text, as the host sends file contents. */
function base64(text: string): string {
  return btoa(String.fromCharCode(...new TextEncoder().encode(text)))
}

const TEMPLATE = [
  '<style>',
  'h1 { font-size: 1.5em; }',
  '/* handout: reading marks begin */ .rd-mark {} /* handout: reading marks end */',
  '</style>',
].join('\n')

const input: HandoutInput = {
  v: 1,
  record: { name: 'csv-export', dir: '/r' },
  explainDir: '/tmp/e',
  template: '/skill/explainer/page.html',
  out: '/r/handout.html',
  log: '/tmp/host.log',
  limits: { pageMs: 30000, runMs: 600000 },
  pages: [
    {
      n: 1,
      title: '書き出しの流れ',
      section: '準備',
      markdown: '# 書き出しの流れ\n',
      built: 'pages/001.html',
    },
    {
      n: 2,
      title: '判定の仕組み',
      section: '仕組み',
      markdown: '# 判定の仕組み\n\n```mermaid\nflowchart LR\n  A[書き出す]\n```\n',
      built: 'pages/002.html',
    },
  ],
}

const label = { text: '書き出す', width: 70, height: 24, contentWidth: 70, contentHeight: 24 }
const DIAGRAM_HTML =
  '<div class="diagram"><svg id="p2-d1"><foreignObject width="70" height="24"><div>書き出す</div></foreignObject></svg></div>'

/** What each page renders as, unless a spec says otherwise. */
const renders: Record<number, { report: RenderReport; probe: PageMeasurement }> = {
  1: {
    report: { type: 'rendered', page: 1, diagrams: 0, errors: [], libs: allLibraries },
    probe: { html: '<h1>書き出しの流れ</h1>', diagrams: [] },
  },
  2: {
    report: { type: 'rendered', page: 2, diagrams: 1, errors: [], libs: allLibraries },
    probe: { html: `<h1>判定の仕組み</h1>${DIAGRAM_HTML}`, diagrams: [{ id: 'p2-d1', labels: [label] }] },
  },
}

const workingCheck = {
  ready: true,
  pages: 2,
  pageNumber: '1/2',
  secondShown: true,
  diagrams: [{ id: 'p2-d1', labels: ['書き出す'] }],
  brokenImages: [],
}

/** A host that answers from the given parts and records every request; `verify` keeps the HTML it got. */
function fakeHost(overrides: { files?: Record<string, string>; renders?: typeof renders; check?: unknown }) {
  const requests: HostRequest[] = []
  const files: Record<string, string> = overrides.files ?? {
    '/skill/explainer/page.html': base64(TEMPLATE),
    '/tmp/e/vendor/highlight.css': base64('.hljs { color: #c9d1d9; }'),
  }
  const pages = overrides.renders ?? renders
  const host = async (request: HostRequest): Promise<HostReply> => {
    requests.push(request)
    if (request.type === 'read') {
      const file = files[request.path]
      return file === undefined
        ? { type: 'unreadable', message: 'no such file' }
        : { type: 'file', base64: file }
    }
    if (request.type === 'render') {
      const rendered = pages[request.page]
      if (!rendered) throw new Error(`no page ${request.page}`)
      return { type: 'rendered', ...rendered }
    }
    return { type: 'verified', probe: overrides.check ?? workingCheck }
  }
  return { host, requests }
}

const dependencies = (host: ReturnType<typeof fakeHost>['host']) => ({
  host,
  handoutCss: '.page { padding: 16px; }',
  controller: { source: 'void 0', sha256: 'c2hh' },
})

test('a Record that passes every check becomes one verified Handout with its page and diagram counts', async () => {
  // Arrange
  const { host, requests } = fakeHost({})

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toMatchObject({ ok: true, pages: 2, diagrams: 1, warnings: [] })
  expect(requests.map((request) => request.type)).toEqual(['read', 'read', 'render', 'render', 'verify'])
  const html = outcome.ok ? outcome.html : ''
  expect(html).toContain('<meta name="dw-handout" content="1">')
  expect(html).toContain('<div>書き出す</div>')
  expect(html).not.toContain('.rd-mark')
})

test('a secret stops the export before a single page is rendered', async () => {
  // Arrange
  const { host, requests } = fakeHost({})
  const leaking = {
    ...input,
    pages: input.pages.map((page) =>
      page.n === 1 ? { ...page, markdown: `# 書き出しの流れ\n\n${GITHUB_TOKEN}\n` } : page,
    ),
  }

  // Act
  const outcome = await buildHandout(leaking, dependencies(host))

  // Assert
  expect(outcome).toEqual({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_SECRET',
        message: 'page 1:3: a secret shape (prefixed-api-key); remove the value from the page',
        page: 1,
        line: 3,
        pattern: 'prefixed-api-key',
      },
    ],
  })
  expect(requests).toEqual([])
})

test('a page.html without its markers stops the export before rendering', async () => {
  // Arrange
  const { host, requests } = fakeHost({
    files: {
      '/skill/explainer/page.html': base64('<style>h1 {}</style>'),
      '/tmp/e/vendor/highlight.css': base64(''),
    },
  })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toEqual({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_TEMPLATE',
        message: 'explainer/page.html: the reading-marks markers are missing from its <style>',
      },
    ],
  })
  expect(requests.some((request) => request.type === 'render')).toBe(false)
})

test('a broken diagram stops the export after every page was rendered, and nothing is verified', async () => {
  // Arrange
  const broken = {
    ...renders,
    2: {
      report: {
        type: 'rendered' as const,
        page: 2,
        diagrams: 1,
        errors: ['diagram 1: Parse error on line 2'],
        libs: allLibraries,
      },
      probe: { html: '<h1>判定の仕組み</h1>', diagrams: [{ id: '', labels: [] }] },
    },
  }
  const { host, requests } = fakeHost({ renders: broken })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toEqual({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_DIAGRAM',
        message: 'page 2:3: diagram 1 did not render: Parse error on line 2',
        page: 2,
        diagram: 1,
        line: 3,
      },
    ],
  })
  expect(requests.some((request) => request.type === 'verify')).toBe(false)
})

test('a library missing from every page is reported once, not once per page', async () => {
  // Arrange
  const withoutMermaid: RenderReport['libs'] = ['marked', 'highlight', 'highlight-http', 'purify']
  const missing = {
    1: { ...renders[1]!, report: { ...renders[1]!.report, libs: withoutMermaid } },
    2: { ...renders[2]!, report: { ...renders[2]!.report, libs: withoutMermaid } },
  }
  const { host } = fakeHost({ renders: missing })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toEqual({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_VENDOR',
        message: 'page 1 rendered without mermaid: the explainer libraries did not load (run dw doctor)',
        page: 1,
      },
    ],
  })
})

test('a finished file whose labels were lost is not handed over as verified', async () => {
  // Arrange
  const { host } = fakeHost({ check: { ...workingCheck, diagrams: [{ id: 'p2-d1', labels: [] }] } })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toEqual({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_VERIFY',
        message: 'the finished Handout lost labels of diagram 1 on page 2: 「書き出す」',
        page: 2,
        diagram: 1,
      },
    ],
  })
})

test('a host reply that breaks the contract is the host’s failure, not the page’s', async () => {
  // Arrange
  const { host } = fakeHost({ check: { ready: 'yes' } })

  // Act
  const build = buildHandout(input, dependencies(host))

  // Assert
  await expect(build).rejects.toThrow()
})

test('a signed link the source spelled with &amp; stops the export once the page is rendered, before anything is verified', async () => {
  // Arrange
  const signature = '0f3a'.repeat(16)
  const disguised = {
    ...renders,
    1: {
      report: { type: 'rendered' as const, page: 1, diagrams: 0, errors: [], libs: allLibraries },
      probe: {
        html: `<h1>書き出しの流れ</h1><p><a href="https://docs.test/a?expires=1&amp;signature=${signature}">設計メモ</a></p>`,
        diagrams: [],
      },
    },
  }
  const { host, requests } = fakeHost({ renders: disguised })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toEqual({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_SECRET',
        message:
          'page 1: a secret shape (signed-url-parameter) in the page as rendered (the source spells it with HTML entities or escapes); remove the value from the page',
        page: 1,
        pattern: 'signed-url-parameter',
      },
    ],
  })
  expect(requests.some((request) => request.type === 'verify')).toBe(false)
})

test('a link to a file on this Mac reaches the agent as a warning while the Handout is still written', async () => {
  // Arrange
  const linking = {
    ...renders,
    1: {
      report: { type: 'rendered' as const, page: 1, diagrams: 0, errors: [], libs: allLibraries },
      probe: { html: '<h1>書き出しの流れ</h1><p><a href="02-設定.md">次のページ</a></p>', diagrams: [] },
    },
  }
  const { host } = fakeHost({ renders: linking })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toMatchObject({
    ok: true,
    warnings: [
      { message: "links to 02-設定.md, a file on this Mac: the colleague's copy cannot open it", page: 1 },
    ],
  })
})

test('a video stops the export before anything is verified: the colleague would get a dead player', async () => {
  // Arrange
  const withVideo = {
    ...renders,
    1: {
      report: { type: 'rendered' as const, page: 1, diagrams: 0, errors: [], libs: allLibraries },
      probe: { html: '<h1>書き出しの流れ</h1><video src="demo.mov" controls></video>', diagrams: [] },
    },
  }
  const { host, requests } = fakeHost({ renders: withVideo })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toMatchObject({ ok: false, diagnostics: [{ code: 'HANDOUT_IMAGE', page: 1 }] })
  expect(requests.some((request) => request.type === 'verify')).toBe(false)
})

test('a diagram that draws a shape from another file stops the export, rather than losing that shape to the sanitizer', async () => {
  // Arrange
  const withUse = {
    ...renders,
    1: {
      report: { type: 'rendered' as const, page: 1, diagrams: 0, errors: [], libs: allLibraries },
      probe: { html: '<h1>書き出しの流れ</h1><svg><use href="parts.svg#box"></use></svg>', diagrams: [] },
    },
  }
  const { host, requests } = fakeHost({ renders: withUse })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toMatchObject({
    ok: false,
    diagnostics: [
      {
        code: 'HANDOUT_IMAGE',
        message:
          'page 1: the use element loads parts.svg#box, which a Handout does not carry: show the picture with an image instead',
        page: 1,
      },
    ],
  })
  expect(requests.some((request) => request.type === 'verify')).toBe(false)
})

test('a link to a local file reaches the agent as a warning even where the sanitizer removes the address', async () => {
  // Arrange
  const linking = {
    ...renders,
    1: {
      report: { type: 'rendered' as const, page: 1, diagrams: 0, errors: [], libs: allLibraries },
      probe: {
        html: '<h1>書き出しの流れ</h1><p><a href="file:///Users/u/notes.md">メモ</a></p>',
        diagrams: [],
      },
    },
  }
  const { host } = fakeHost({ renders: linking })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toMatchObject({
    ok: true,
    warnings: [
      {
        message: "links to file:///Users/u/notes.md, a file on this Mac: the colleague's copy cannot open it",
        page: 1,
      },
    ],
  })
})

test('a Handout with screenshots tells the agent that what a picture shows is not checked', async () => {
  // Arrange
  const withPicture = {
    ...renders,
    1: {
      report: { type: 'rendered' as const, page: 1, diagrams: 0, errors: [], libs: allLibraries },
      probe: { html: '<h1>書き出しの流れ</h1><p><img src="shot.png" alt="画面"></p>', diagrams: [] },
    },
  }
  const { host } = fakeHost({
    renders: withPicture,
    files: {
      '/skill/explainer/page.html': base64(TEMPLATE),
      '/tmp/e/vendor/highlight.css': base64('.hljs { color: #c9d1d9; }'),
      '/r/pages/shot.png':
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    },
  })

  // Act
  const outcome = await buildHandout(input, dependencies(host))

  // Assert
  expect(outcome).toMatchObject({
    ok: true,
    warnings: [
      {
        message:
          '1 picture(s) embedded: the export checks their bytes and metadata, not what they show; look at each one before sharing',
      },
    ],
  })
})
