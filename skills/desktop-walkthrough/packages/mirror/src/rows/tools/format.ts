/**
 * Wording helpers of the tool rows: paths, sizes, counts and times the way the terminal writes them.
 *
 * Why it exists: titles, results and folded lines all write the same few things (`~/x/y.ts`,
 * `1.5KB`, `2 files`, `1m 30s`); one copy keeps them alike. Called by the tool row components.
 */
import { formatDuration } from '../duration'

/**
 * A file path as the terminal shows it in a title.
 *
 * The terminal shortens a path inside the working directory to its relative form; the Mirror does not
 * know the working directory, so only the home folder is shortened (`/Users/name/x` becomes `~/x`).
 *
 * @param path - The path as the model gave it.
 * @returns The path to draw; a notice for a path with a NUL byte.
 */
export function displayPath(path: string): string {
  if (path.includes('\0')) return 'Path hidden (unsupported characters)'
  return path.replace(/^\/(?:Users|home)\/[^/]+(?=\/|$)/, '~')
}

/**
 * A byte count as the terminal writes sizes: `512 bytes`, `1.5KB`, `2MB`.
 *
 * @param bytes - Bytes.
 * @returns Under 1024 `N bytes`; above one decimal with a trailing `.0` dropped and no space.
 */
export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} ${bytes === 1 ? 'byte' : 'bytes'}`
  const units = ['KB', 'MB', 'GB'] as const
  let value = bytes
  let unit: (typeof units)[number] = 'KB'
  for (const candidate of units) {
    value /= 1024
    unit = candidate
    if (value < 1024) break
  }
  return `${value.toFixed(1).replace(/\.0$/, '')}${unit}`
}

/**
 * A token count in the short form of the agent lines: `830`, `1.2k`, `12k`, `1.5m`.
 *
 * @param tokens - Tokens.
 * @returns The short wording.
 */
export function formatTokens(tokens: number): string {
  if (tokens < 1000) return String(tokens)
  if (tokens < 10_000) return `${(tokens / 1000).toFixed(1).replace(/\.0$/, '')}k`
  if (tokens < 1_000_000) return `${Math.round(tokens / 1000)}k`
  return `${(tokens / 1_000_000).toFixed(1).replace(/\.0$/, '')}m`
}

/**
 * A time limit the way a timeout is written: trailing zero units dropped (`2m`, `1m 30s`, `45s`).
 *
 * @param milliseconds - The limit in milliseconds.
 * @returns The wording.
 */
export function formatTimeout(milliseconds: number): string {
  return formatDuration(milliseconds).replace(/( 0[smh])+$/, '')
}

/**
 * A count with its noun, singular for exactly 1.
 *
 * @param count - The number.
 * @param singular - The noun for one.
 * @param plural - The noun for any other number; the singular with an `s` when omitted.
 * @returns For example `1 file`, `3 files`, `0 files`.
 */
export function countOf(count: number, singular: string, plural = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : plural}`
}

/**
 * Only the noun of a {@link countOf}, for rows that draw the number in bold on its own.
 *
 * @param count - The number.
 * @param singular - The noun for one.
 * @param plural - The noun for any other number; the singular with an `s` when omitted.
 * @returns The noun that fits the number.
 */
export function nounFor(count: number, singular: string, plural = `${singular}s`): string {
  return count === 1 ? singular : plural
}

/**
 * Put every run of white space into a single space, as titles do with a description.
 *
 * @param text - Any text.
 * @returns The text on one line.
 */
export function collapseSpace(text: string): string {
  return text.replaceAll(/\s+/g, ' ').trim()
}
