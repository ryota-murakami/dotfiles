/**
 * Syntax colouring of the code a tool result shows (a Write preview, a notebook cell), split by line.
 *
 * Why it exists: the preview is drawn one row per line with a gutter, but the highlighter returns one
 * HTML string in which a token (a block comment) can span lines; this closes and reopens the spans at
 * every line break. Called by {@link CodePreview}.
 */
import { highlightCode, isKnownLanguage } from '../../markdown/highlight'

/** Highlighter language names by file extension. */
const LANGUAGE_BY_EXTENSION: Readonly<Record<string, string>> = {
  ts: 'typescript',
  tsx: 'typescript',
  mts: 'typescript',
  cts: 'typescript',
  js: 'javascript',
  jsx: 'javascript',
  mjs: 'javascript',
  cjs: 'javascript',
  json: 'json',
  md: 'markdown',
  py: 'python',
  sh: 'bash',
  bash: 'bash',
  zsh: 'bash',
  css: 'css',
  html: 'xml',
  xml: 'xml',
  svg: 'xml',
  yml: 'yaml',
  yaml: 'yaml',
  rs: 'rust',
  go: 'go',
  rb: 'ruby',
  java: 'java',
  c: 'c',
  h: 'c',
  cpp: 'cpp',
  swift: 'swift',
  sql: 'sql',
}

/**
 * The highlighter language for a file path.
 *
 * @param path - A file path.
 * @returns A language name the highlighter knows; undefined for an unknown extension.
 */
export function languageForPath(path: string): string | undefined {
  const extension = /\.([A-Za-z0-9]+)$/.exec(path)?.[1]?.toLowerCase()
  const language = extension === undefined ? undefined : LANGUAGE_BY_EXTENSION[extension]
  return language !== undefined && isKnownLanguage(language) ? language : undefined
}

/**
 * Colour a code text and return it line by line.
 *
 * @param lines - The code's lines.
 * @param language - A language name for which the highlighter has a grammar.
 * @returns One HTML string per line (the text is escaped; tokens are `hljs-*` spans), same length as `lines`.
 */
export function highlightLines(lines: readonly string[], language: string): string[] {
  const html = highlightCode(lines.join('\n'), language)
  const result: string[] = []
  const open: string[] = []
  let current = ''
  for (const part of html.split(/(<\/?span[^>]*>|\n)/)) {
    if (part === '\n') {
      // A token that runs over the line break is closed here and reopened on the next line
      result.push(current + '</span>'.repeat(open.length))
      current = open.join('')
    } else if (part.startsWith('<span')) {
      open.push(part)
      current += part
    } else if (part === '</span>') {
      open.pop()
      current += part
    } else current += part
  }
  result.push(current + '</span>'.repeat(open.length))
  return result
}
