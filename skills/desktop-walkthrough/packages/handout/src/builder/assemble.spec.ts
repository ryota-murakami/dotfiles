import { expect, test } from 'vitest'

import { assembleHandout } from './assemble'

const parts = {
  pages: [
    { n: 1, title: '書き出しの流れ', section: '準備', html: '<h1>書き出しの流れ</h1><p>本文</p>' },
    { n: 2, title: 'A & <B>', section: '仕組み', html: '<h1>A &amp; &lt;B&gt;</h1>' },
  ],
  pageCss: 'h1 { font-size: 1.5em; }',
  highlightCss: '.hljs { color: #c9d1d9; }',
  handoutCss: '.page { padding: 16px; }',
  controller: {
    source: 'document.documentElement.setAttribute("data-handout-ready", "")',
    sha256: 'c2hhMjU2',
  },
}

test('a Handout starts with the exact head dw and the host require before they replace a file', () => {
  // Arrange
  const expectedHead =
    '<!doctype html>\n<html lang="ja">\n<head>\n<meta charset="utf-8">\n<meta name="dw-handout" content="1">\n'

  // Act
  const html = assembleHandout(parts)

  // Assert
  expect(html.slice(0, expectedHead.length)).toBe(expectedHead)
})

test('the CSP lets only the controller run, by its hash, and loads nothing from outside', () => {
  // Arrange
  const expected =
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'sha256-c2hhMjU2'; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'\">"

  // Act
  const html = assembleHandout(parts)

  // Assert
  expect(html).toContain(expected)
  expect(html).toContain(`<script>${parts.controller.source}</script>`)
})

test('every page is in the file in reading order, readable even where the controller never runs', () => {
  // Arrange
  const document = new DOMParser().parseFromString(assembleHandout(parts), 'text/html')

  // Act
  const pages = Array.from(document.querySelectorAll('article.page')).map((page) => ({
    id: page.id,
    hidden: page.hasAttribute('hidden'),
    section: page.querySelector('.section')?.textContent,
  }))

  // Assert
  expect(pages).toEqual([
    { id: 'page-1', hidden: false, section: '準備' },
    { id: 'page-2', hidden: false, section: '仕組み' },
  ])
})

test('the file is titled by its first page and keeps titles with markup characters as text', () => {
  // Arrange
  const document = new DOMParser().parseFromString(assembleHandout(parts), 'text/html')

  // Act
  const toc = JSON.parse(document.getElementById('handout-toc')?.textContent ?? '[]')

  // Assert
  expect(document.title).toBe('書き出しの流れ')
  expect(toc).toEqual([
    { n: 1, title: '書き出しの流れ', section: '準備' },
    { n: 2, title: 'A & <B>', section: '仕組み' },
  ])
})

test('a title that spells </script> cannot end the table of contents early', () => {
  // Arrange
  const withScriptTitle = {
    ...parts,
    pages: [{ n: 1, title: '</script><script>alert(1)</script>', section: '', html: '<p>x</p>' }],
  }

  // Act
  const html = assembleHandout(withScriptTitle)

  // Assert
  expect(html).toContain('\\u003c/script>\\u003cscript>alert(1)\\u003c/script>')
  expect(html.match(/<script>/g)).toHaveLength(1)
})

test('a controller that would cut its own script element short is refused', () => {
  // Arrange
  const broken = { ...parts, controller: { source: 'x = "</script>"', sha256: 'eA==' } }

  // Act
  const assemble = () => assembleHandout(broken)

  // Assert
  expect(assemble).toThrow('the controller source contains "</script"')
})

test('a Record whose page numbers have gaps is still addressed page 1, 2, 3 in the Handout', () => {
  // Arrange
  const withGaps = {
    ...parts,
    pages: [
      { n: 1, title: 'A', section: '', html: '<p>a</p>' },
      { n: 3, title: 'C', section: '', html: '<p>c</p>' },
      { n: 7, title: 'G', section: '', html: '<p>g</p>' },
    ],
  }
  const document = new DOMParser().parseFromString(assembleHandout(withGaps), 'text/html')

  // Act
  const pages = Array.from(document.querySelectorAll('article.page')).map((page) => [
    page.id,
    page.getAttribute('data-n'),
  ])

  // Assert
  expect(pages).toEqual([
    ['page-1', '1'],
    ['page-2', '3'],
    ['page-3', '7'],
  ])
})

test('a style sheet that would end the style element early is refused, so no CSS text turns into page markup', () => {
  // Arrange
  const broken = { ...parts, highlightCss: '.hljs { color: red } </style><p>外</p>' }

  // Act
  const assemble = () => assembleHandout(broken)

  // Assert
  expect(assemble).toThrow('the highlight.js theme contains "</style"')
})

test('a controller holding "<!--" is refused: next to "<script" it changes where the browser ends the element', () => {
  // Arrange
  const broken = { ...parts, controller: { source: 'const a = "<!--"', sha256: 'eA==' } }

  // Act
  const assemble = () => assembleHandout(broken)

  // Assert
  expect(assemble).toThrow('the controller source contains "<!--"')
})
