/**
 * Word-level comparison of a removed line with the line that replaces it.
 *
 * Why it exists: the terminal paints the words that changed between a removed row and its added
 * partner in a brighter background (`tools.md`, section 3.5); this finds them. Called by {@link DiffView}
 * for each pair of rows.
 */

/** A stretch of a line, changed or not. */
export type WordSpan = { text: string; isChanged: boolean }

/** The two lines of a pair, cut into spans. */
export type WordDiff = { removed: WordSpan[]; added: WordSpan[] }

/** The share of changed characters above which the terminal leaves a pair without word highlights. */
const MAX_CHANGED_SHARE = 0.4
/** The most tokens of a line the comparison reads; longer lines are left without word highlights. */
const MAX_TOKENS = 300

/** Words, runs of white space and single punctuation marks. */
const TOKEN = /[\p{L}\p{N}_]+|\s+|[^\s\p{L}\p{N}_]/gu

/** Merge neighbouring tokens of the same kind into one span. */
function toSpans(tokens: readonly string[], isChanged: readonly boolean[]): WordSpan[] {
  const spans: WordSpan[] = []
  tokens.forEach((text, index) => {
    const changed = isChanged[index] === true
    const last = spans.at(-1)
    if (last && last.isChanged === changed) last.text += text
    else spans.push({ text, isChanged: changed })
  })
  return spans
}

/**
 * Compare two lines word by word.
 *
 * @param removed - The old line.
 * @param added - The new line.
 * @returns Both lines as spans, the words outside their longest common run marked changed; undefined
 *   when more than 40 percent of the characters differ, or when a line is too long to compare.
 */
export function diffWords(removed: string, added: string): WordDiff | undefined {
  const a = removed.match(TOKEN) ?? []
  const b = added.match(TOKEN) ?? []
  if (a.length > MAX_TOKENS || b.length > MAX_TOKENS) return undefined
  // Longest common subsequence of tokens, as a table of suffix lengths
  const table = Array.from({ length: a.length + 1 }, () => Array.from({ length: b.length + 1 }, () => 0))
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      const row = table[i]
      const below = table[i + 1]
      if (!row || !below) continue
      row[j] = a[i] === b[j] ? (below[j + 1] ?? 0) + 1 : Math.max(below[j] ?? 0, row[j + 1] ?? 0)
    }
  }
  const aChanged = Array.from({ length: a.length }, () => true)
  const bChanged = Array.from({ length: b.length }, () => true)
  let i = 0
  let j = 0
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      aChanged[i] = false
      bChanged[j] = false
      i++
      j++
    } else if ((table[i + 1]?.[j] ?? 0) >= (table[i]?.[j + 1] ?? 0)) i++
    else j++
  }
  const changedChars =
    a.reduce((sum, token, index) => sum + (aChanged[index] ? token.length : 0), 0) +
    b.reduce((sum, token, index) => sum + (bChanged[index] ? token.length : 0), 0)
  const total = removed.length + added.length
  if (total === 0 || changedChars / total > MAX_CHANGED_SHARE) return undefined
  return { removed: toSpans(a, aChanged), added: toSpans(b, bChanged) }
}
