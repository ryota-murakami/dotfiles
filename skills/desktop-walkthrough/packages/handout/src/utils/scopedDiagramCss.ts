/**
 * Keep the rules of a diagram's style sheet that stay inside its SVG, and drop the rest.
 *
 * Why it exists: an SVG's style sheet applies to the whole document, and a Handout is one document
 * holding every page. mermaid scopes each rule it writes by the diagram's id (`#p2-d1 .node rect`)
 * and adds the keyframes of its animated edges; a rule scoped otherwise (`body`, `#page-2`, a sibling
 * of the SVG through `+` or `~`) or an at-rule (`@media`, `@import`) was not written by mermaid, and
 * would style the rest of the Handout. Called by {@link sanitizePage} for each diagram's `<style>`.
 *
 * @param css - The style sheet's text.
 * @param svgId - The id of the SVG the sheet belongs to (`p2-d1`).
 * @param parser - The document whose CSS parser reads the sheet: the sheet is added to it for a
 *   moment as `<style media="not all">`, which applies to nothing.
 * @returns The rules kept, as the parser writes them, one per line; empty when none stays.
 *
 * @example
 * scopedDiagramCss('#p2-d1 .node{fill:red}body{display:none}', 'p2-d1', document)
 * // '#p2-d1 .node { fill: red; }'
 */
export function scopedDiagramCss(css: string, svgId: string, parser: Document): string {
  const probe = parser.createElement('style')
  probe.media = 'not all'
  probe.textContent = css
  parser.head.append(probe)
  try {
    return Array.from(probe.sheet?.cssRules ?? [])
      .filter((rule) => staysInDiagram(rule, `#${svgId}`))
      .map((rule) => rule.cssText)
      .join('\n')
  } finally {
    probe.remove()
  }
}

/**
 * Whether a rule styles nothing outside the SVG whose id selector is SCOPE: keyframes (they select
 * nothing), or a style rule whose every selector starts at the SVG and steps to no sibling of it.
 *
 * @param rule - A top-level rule of the sheet.
 * @param scope - The SVG's id selector (`#p2-d1`).
 * @returns Whether the rule may stay.
 *
 * @example
 * staysInDiagram(ruleOf('#p2-d1 .node{fill:red}'), '#p2-d1') // true
 * staysInDiagram(ruleOf('#p2-d1 + p{color:red}'), '#p2-d1')  // false
 */
function staysInDiagram(rule: CSSRule, scope: string): boolean {
  if (rule instanceof CSSKeyframesRule) return true
  if (!(rule instanceof CSSStyleRule)) return false
  // A nested rule could step out through `&`: mermaid writes none
  if ('cssRules' in rule && rule.cssRules.length > 0) return false
  return selectorsOf(rule.selectorText).every((selector) => {
    const rest = selector.slice(scope.length)
    // The id ends there (`#p2-d10` is another diagram's), and no combinator reaches a sibling
    return (
      selector.startsWith(scope) &&
      !/^[\w\\\u{80}-\u{10FFFF}-]/u.test(rest) &&
      !/[+~]/.test(outsideBrackets(rest))
    )
  })
}

/**
 * The selectors of a selector list: split at its commas, but not at one inside `( )`, `[ ]` or quotes.
 *
 * @param selectorText - A style rule's selector list, as the parser writes it.
 * @returns Each selector, trimmed.
 *
 * @example
 * selectorsOf('#a :is(.b, .c), #a [d="e,f"]') // ['#a :is(.b, .c)', '#a [d="e,f"]']
 */
function selectorsOf(selectorText: string): string[] {
  const selectors: string[] = []
  let depth = 0
  let quote = ''
  let start = 0
  for (let index = 0; index < selectorText.length; index++) {
    const character = selectorText[index] ?? ''
    // An escaped character is never a comma, a bracket or a quote of the list
    if (character === '\\') {
      index++
      continue
    }
    if (quote !== '') {
      if (character === quote) quote = ''
      continue
    }
    if (character === '"' || character === "'") quote = character
    else if (character === '(' || character === '[') depth++
    else if (character === ')' || character === ']') depth--
    else if (character === ',' && depth === 0) {
      selectors.push(selectorText.slice(start, index).trim())
      start = index + 1
    }
  }
  selectors.push(selectorText.slice(start).trim())
  return selectors
}

/**
 * A selector with what is inside `( )`, `[ ]` and quotes left out, so that its own combinators can
 * be read (`2n+1` and `[class~="a"]` hold no combinator).
 *
 * @param selector - One selector.
 * @returns The selector's text outside every bracket and quote.
 *
 * @example
 * outsideBrackets('g:nth-child(2n+1) + p') // 'g:nth-child + p'
 */
function outsideBrackets(selector: string): string {
  let depth = 0
  let quote = ''
  let outside = ''
  for (let index = 0; index < selector.length; index++) {
    const character = selector[index] ?? ''
    if (character === '\\') {
      // An escaped + or ~ is part of a name: kept out of the combinators
      index++
      continue
    }
    if (quote !== '') {
      if (character === quote) quote = ''
      continue
    }
    if (character === '"' || character === "'") quote = character
    else if (character === '(' || character === '[') depth++
    else if (character === ')' || character === ']') depth--
    else if (depth === 0) outside += character
  }
  return outside
}
