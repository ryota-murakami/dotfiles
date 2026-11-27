import { expect, test } from 'vitest'

import { scanForSecrets } from './scan'

// Fake credentials are assembled at run time so secret scanners do not flag this public file.
const SIGNATURE = '0f3a'.repeat(16)
const GITHUB_TOKEN = ['ghp', 'y'.repeat(36)].join('_')

test('a signed link behind harmless link text stops the export with its page, line and shape', () => {
  // Arrange
  const pages = [
    {
      n: 2,
      title: '設計',
      section: '仕組み',
      source: 'pages/02-設計.md',
      markdown: `# 設計\n\n詳しくは [設計メモ](https://docs.test/a?signature=${SIGNATURE}) を見てください。\n`,
      built: 'pages/002.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message: 'pages/02-設計.md:3: a secret shape (signed-url-parameter); remove the value from the page',
      page: 2,
      line: 3,
      pattern: 'signed-url-parameter',
    },
  ])
})

test('no message of the scan carries the secret value', () => {
  // Arrange
  const pages = [
    {
      n: 1,
      title: `token ${GITHUB_TOKEN}`,
      section: `section ${GITHUB_TOKEN}`,
      source: 'pages/01-a.md',
      markdown: `# A\n\n${GITHUB_TOKEN}\n`,
      built: 'pages/001.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toHaveLength(3)
  expect(JSON.stringify(diagnostics)).not.toContain(GITHUB_TOKEN)
})

test('a secret in a title given with --title stops the export, naming the title', () => {
  // Arrange
  const pages = [
    {
      n: 4,
      title: `接続先 ${GITHUB_TOKEN}`,
      section: '',
      source: 'pages/04-接続先.md',
      markdown: '本文だけのページ\n',
      built: 'pages/004.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message: 'page 4: a secret shape (prefixed-api-key) in its title; give the page another title',
      page: 4,
      pattern: 'prefixed-api-key',
    },
  ])
})

test('a title that is the page’s own heading is reported once, at its source line', () => {
  // Arrange
  const title = `接続先 ${GITHUB_TOKEN}`
  const pages = [
    {
      n: 4,
      title,
      section: '',
      source: 'pages/04-接続先.md',
      markdown: `# ${title}\n`,
      built: 'pages/004.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message: 'pages/04-接続先.md:1: a secret shape (prefixed-api-key); remove the value from the page',
      page: 4,
      line: 1,
      pattern: 'prefixed-api-key',
    },
  ])
})

test('a secret in a section name stops the export, pointing at sections.tsv', () => {
  // Arrange
  const pages = [
    {
      n: 5,
      title: '手順',
      section: `準備 ${GITHUB_TOKEN}`,
      source: 'pages/05-手順.md',
      markdown: '# 手順\n',
      built: 'pages/005.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message: 'page 5: a secret shape (prefixed-api-key) in its section name (pages/sections.tsv)',
      page: 5,
      pattern: 'prefixed-api-key',
    },
  ])
})

test('a Record that only says where secrets come from passes the scan', () => {
  // Arrange
  const pages = [
    {
      n: 1,
      title: '設定',
      section: '準備',
      source: 'pages/01-設定.md',
      markdown: '# 設定\n\n```sh\nexport API_TOKEN="$(op read op://vault/api/token)"\n```\n',
      built: 'pages/001.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([])
})
