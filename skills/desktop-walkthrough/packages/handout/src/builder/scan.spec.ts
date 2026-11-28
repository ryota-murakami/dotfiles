import { expect, test } from 'vitest'

import { scanForSecrets, scanRenderedPage } from './scan'

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
      message: 'page 2:3: a secret shape (signed-url-parameter); remove the value from the page',
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
      message: 'page 4:1: a secret shape (prefixed-api-key); remove the value from the page',
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
      markdown: '# 設定\n\n```sh\nexport API_TOKEN="$(op read op://vault/api/token)"\n```\n',
      built: 'pages/001.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a title given with --title is checked on its own, even when the page holds the value inside a longer word', () => {
  // Arrange
  const pages = [
    {
      n: 4,
      title: GITHUB_TOKEN,
      section: '',
      markdown: `# 見出し\n\n識別子 x${GITHUB_TOKEN} を使います\n`,
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

test('a heading that gives the page its title is reported once, at its line', () => {
  // Arrange
  const pages = [
    {
      n: 6,
      title: `設定 ${GITHUB_TOKEN}`,
      section: '',
      markdown: `# 設定 ${GITHUB_TOKEN}\n\n本文\n`,
      built: 'pages/006.html',
    },
  ]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message: 'page 6:1: a secret shape (prefixed-api-key); remove the value from the page',
      page: 6,
      line: 1,
      pattern: 'prefixed-api-key',
    },
  ])
})

test('a signed link the source spelled with &amp; is caught in the page as rendered, where it works again', () => {
  // Arrange
  const page = {
    n: 2,
    title: '設計',
    section: '',
    markdown: `<a href="https://docs.test/a?expires=1&amp;signature=${SIGNATURE}">設計メモ</a>\n`,
    built: 'pages/002.html',
  }
  const html = `<p><a href="https://docs.test/a?expires=1&amp;signature=${SIGNATURE}">設計メモ</a></p>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(scanForSecrets([page])).toEqual([])
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message:
        'page 2: a secret shape (signed-url-parameter) in the page as rendered (the source spells it with HTML entities or escapes); remove the value from the page',
      page: 2,
      pattern: 'signed-url-parameter',
    },
  ])
})

test('an embedded image is not read as text by the rendered-page scan', () => {
  // Arrange
  const page = {
    n: 1,
    title: '画面',
    section: '',
    markdown: '',
    built: 'pages/001.html',
  }
  const html = `<p><img src="data:image/png;base64,${'iVBORw0KGgo'.repeat(20)}" alt="一覧"></p>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})

// An AWS access key id of the documented example shape, assembled at run time like the values above
const ACCESS_KEY_ID = ['AKIA', 'IOSFODNN7EXAMPLE'].join('')

test('a secret an attribute spells with entities after "data:" is caught in the page as rendered', () => {
  // Arrange
  const spelled = `&#65;${ACCESS_KEY_ID.slice(1)}`
  const page = {
    n: 3,
    title: '一覧',
    section: '',
    markdown: `<span title="data:,${spelled}">一覧</span>\n`,
    built: 'pages/003.html',
  }
  const html = `<p><span title="data:,${spelled}">一覧</span></p>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(scanForSecrets([page])).toEqual([])
  expect(diagnostics).toEqual([
    {
      code: 'HANDOUT_SECRET',
      message:
        'page 3: a secret shape (aws-access-key-id) in the page as rendered (the source spells it with HTML entities or escapes); remove the value from the page',
      page: 3,
      pattern: 'aws-access-key-id',
    },
  ])
})

test('a link whose address starts with "data:" is read as text: only an embedded image source is skipped', () => {
  // Arrange
  const page = { n: 1, title: '資料', section: '', markdown: '', built: 'pages/001.html' }
  const html = `<p><a href="data:text/plain,${ACCESS_KEY_ID}">資料</a></p>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.pattern)).toEqual(['aws-access-key-id'])
})

test('the image an inline SVG draws is not read as text once it is embedded', () => {
  // Arrange
  const page = { n: 1, title: '図', section: '', markdown: '', built: 'pages/001.html' }
  const html = `<svg viewBox="0 0 10 10"><image href="data:image/png;base64,${'iVBORw0KGgo'.repeat(20)}"></image></svg>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(diagnostics).toEqual([])
})

test('a secret in a page title is never printed through the page’s file name: messages name the page by number', () => {
  // Arrange
  const bearer = `Bearer ${'a1b2'.repeat(6)}`
  const pages = [{ n: 7, title: bearer, section: '', markdown: `# ${bearer}\n`, built: 'pages/007.html' }]

  // Act
  const diagnostics = scanForSecrets(pages)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.message)).toEqual([
    'page 7:1: a secret shape (authorization-header); remove the value from the page',
  ])
  expect(JSON.stringify(diagnostics)).not.toContain('a1b2')
})

test('a key the source spells with entities right after a line break is caught: the break is a boundary the reader sees', () => {
  // Arrange
  const spelled = `&#65;${ACCESS_KEY_ID.slice(1)}`
  const page = { n: 3, title: '鍵', section: '', markdown: `note<br>${spelled}\n`, built: 'pages/003.html' }
  const html = `<p>note<br>${spelled}</p>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(scanForSecrets([page])).toEqual([])
  expect(diagnostics.map((diagnostic) => diagnostic.pattern)).toEqual(['aws-access-key-id'])
})

test('a key held inside a template element is read too: its contents ship in the file', () => {
  // Arrange
  const page = { n: 3, title: '鍵', section: '', markdown: '', built: 'pages/003.html' }
  const html = `<template><p>x${ACCESS_KEY_ID}</p><p>${ACCESS_KEY_ID}</p></template>`

  // Act
  const diagnostics = scanRenderedPage(page, html)

  // Assert
  expect(diagnostics.map((diagnostic) => diagnostic.pattern)).toEqual(['aws-access-key-id'])
})
