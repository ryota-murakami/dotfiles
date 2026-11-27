import { expect, test } from 'vitest'

// A fake credential is assembled at run time so secret scanners do not flag this public file.
const GITHUB_TOKEN = ['ghp', 'y'.repeat(36)].join('_')

test('a failure the host reports during a build reaches it with every secret shape masked', async () => {
  // Arrange
  window.webkit = {
    messageHandlers: {
      host: {
        postMessage: async () => {
          throw new Error(`the probe stopped near ${GITHUB_TOKEN}`)
        },
      },
    },
  }
  await import('./main')
  const input = {
    v: 1,
    record: { name: 'r', dir: '/r' },
    explainDir: '/tmp/explain',
    template: '/skill/explainer/page.html',
    out: '/r/handout.html',
    log: '/tmp/handout.log',
    limits: { pageMs: 30_000, runMs: 600_000 },
    pages: [{ n: 1, title: '画面', section: '', markdown: '# 画面\n', built: 'pages/001.html' }],
  }

  // Act
  const failure = await window.dwHandout?.build(input).catch((error: unknown) => error)

  // Assert
  expect(String(failure)).not.toContain(GITHUB_TOKEN)
  expect(String(failure)).toBe('Error: the probe stopped near ghp_•••')
})
