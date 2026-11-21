/** The most the numbers of a list may reach for lower-case Roman numerals (`iii.`), as Claude Code draws them. */
const MAX_ROMAN = 3999

/**
 * Lower-case Roman numeral of a number.
 *
 * @param value - 1 to 3999.
 * @returns The numeral (`4` gives `iv`).
 */
function toRoman(value: number): string {
  const steps: readonly (readonly [number, string])[] = [
    [1000, 'm'],
    [900, 'cm'],
    [500, 'd'],
    [400, 'cd'],
    [100, 'c'],
    [90, 'xc'],
    [50, 'l'],
    [40, 'xl'],
    [10, 'x'],
    [9, 'ix'],
    [5, 'v'],
    [4, 'iv'],
    [1, 'i'],
  ]
  let rest = value
  let roman = ''
  for (const [amount, letters] of steps) {
    while (rest >= amount) {
      roman += letters
      rest -= amount
    }
  }
  return roman
}

/**
 * Letters for a number the way a spreadsheet names columns (`1` gives `a`, `27` gives `aa`).
 *
 * @param value - 1 or more.
 */
function toLetters(value: number): string {
  let rest = value
  let letters = ''
  while (rest > 0) {
    rest -= 1
    letters = String.fromCharCode(97 + (rest % 26)) + letters
    rest = Math.floor(rest / 26)
  }
  return letters
}

/**
 * The marker a list item wears, by the rules of the terminal: `-` for every unordered item; for an
 * ordered list `1.` at the top, `a.` one level down, `i.` two levels down and `1.` again below that.
 *
 * Why it exists: the markdown renderer needs one marker per item, and the marker's width decides the
 * indent of everything nested in the item. Called by the list renderer.
 *
 * @param isOrdered - Whether the list is numbered.
 * @param number - The item's number in an ordered list (its first number plus its position).
 * @param depth - How many lists the item is nested in (0 at the top).
 * @returns The marker without the space that follows it.
 */
export function listMarker(isOrdered: boolean, number: number, depth: number): string {
  if (!isOrdered) return '-'
  // Roman numerals only while the numbers stay small enough to have one
  if (depth === 2 && number <= MAX_ROMAN) return `${toRoman(number)}.`
  if (depth === 1) return `${toLetters(number)}.`
  return `${number}.`
}
