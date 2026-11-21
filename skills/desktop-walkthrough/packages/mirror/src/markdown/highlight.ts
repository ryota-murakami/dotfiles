import hljs from 'highlight.js/lib/core'
import bash from 'highlight.js/lib/languages/bash'
import c from 'highlight.js/lib/languages/c'
import cpp from 'highlight.js/lib/languages/cpp'
import css from 'highlight.js/lib/languages/css'
import diff from 'highlight.js/lib/languages/diff'
import go from 'highlight.js/lib/languages/go'
import java from 'highlight.js/lib/languages/java'
import javascript from 'highlight.js/lib/languages/javascript'
import json from 'highlight.js/lib/languages/json'
import markdown from 'highlight.js/lib/languages/markdown'
import python from 'highlight.js/lib/languages/python'
import ruby from 'highlight.js/lib/languages/ruby'
import rust from 'highlight.js/lib/languages/rust'
import sql from 'highlight.js/lib/languages/sql'
import swift from 'highlight.js/lib/languages/swift'
import typescript from 'highlight.js/lib/languages/typescript'
import xml from 'highlight.js/lib/languages/xml'
import yaml from 'highlight.js/lib/languages/yaml'

// Only the languages a coding session shows; each one adds to the single HTML file
const LANGUAGES = {
  bash,
  c,
  cpp,
  css,
  diff,
  go,
  java,
  javascript,
  json,
  markdown,
  python,
  ruby,
  rust,
  sql,
  swift,
  typescript,
  xml,
  yaml,
}
for (const [name, definition] of Object.entries(LANGUAGES)) hljs.registerLanguage(name, definition)

/**
 * Whether the highlighter knows a fence's language label.
 *
 * Why it exists: Claude Code draws a fence with a known language in colours, a fence with an unknown
 * one under a dim label line, so the code block needs to ask before it draws. Called by the markdown
 * renderer for every fenced code block.
 *
 * @param language - The label after the opening fence (`ts`, `bash`, …), as written.
 * @returns True when {@link highlightCode} can colour it.
 */
export function isKnownLanguage(language: string): boolean {
  return hljs.getLanguage(language) !== undefined
}

/**
 * Colour a code text.
 *
 * @param code - The code, without its fence.
 * @param language - A label for which {@link isKnownLanguage} is true.
 * @returns HTML in which each token is a `hljs-*` span (the text is escaped); `markdown.css` colours them.
 */
export function highlightCode(code: string, language: string): string {
  return hljs.highlight(code, { language, ignoreIllegals: true }).value
}
