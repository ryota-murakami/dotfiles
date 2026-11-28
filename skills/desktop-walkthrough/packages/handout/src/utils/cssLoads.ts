/**
 * What some CSS loads: the target of each `url(…)`, the strings of `image-set(…)`, and `@import`'s
 * string, quotes trimmed, without the tabs and line feeds a URL drops. A reference within the
 * document (`url(#arrow)`, how a diagram points at its own markers and gradients) loads nothing.
 *
 * Why it exists: a Handout carries only what was checked, so every reader of CSS has to find what a
 * browser would load, however it is spelled (`u\\72l(` is `url(`). Called by
 * {@link unembeddableResources} for a page's styles, and by {@link embedImages} for the styles of an
 * SVG a page shows.
 *
 * @param written - A style attribute, a presentation attribute or a style sheet, as written.
 * @returns The targets that load something.
 *
 * @example
 * cssLoads('fill: url(#gradient); background: image-set("bg.png" 1x)') // ['bg.png']
 * cssLoads('@import "theme.css";')                                     // ['theme.css']
 * cssLoads('background: url("im\\a age.png")')                         // ['image.png']
 */
export function cssLoads(written: string): string[] {
  // CSS lets a name be spelled with escapes (`u\\72l(` is `url(`): read as the browser does
  const css = unescapeCss(written)
  const targets = urlTargets(css)
  // An image-set is read to its own closing parenthesis: an option before a picture may be a function
  // of its own (a gradient). A string, like the set itself, may run unclosed to the end of the text,
  // where CSS ends it (across lines too: an escape may put a line feed inside)
  for (const set of css.matchAll(/image-set\(/gi)) {
    const contents = functionContents(css, (set.index ?? 0) + set[0].length)
    for (const string of contents.matchAll(/(["'])(.*?)(?:\1|$)/gs)) targets.push(string[2] ?? '')
  }
  // @import's string may follow at once or after comments, as CSS reads its tokens
  for (const imported of css.matchAll(/@import(?:\s|\/\*.*?\*\/)*(["'])(.*?)(?:\1|$)/gis))
    targets.push(imported[2] ?? '')
  // A URL drops the tabs and line feeds it holds, as the browser's URL parser does: `im\a age.png`
  // loads image.png, and `\a #arrow` is the marker #arrow
  return targets
    .map((target) => target.replace(/[\t\n\r]/g, '').trim())
    .filter((target) => target !== '' && !target.startsWith('#'))
}

/**
 * The target of each `url(…)` in decoded CSS, read as CSS reads it: a quoted string to its closing
 * quote, anything else to the closing parenthesis, and either one to the end of the text when it is
 * never closed (CSS ends both there, and the URL still loads). Called by {@link cssLoads}.
 *
 * @param css - CSS text, its escapes decoded ({@link unescapeCss}).
 * @returns Each target as written, quotes left out, not yet trimmed.
 *
 * @example
 * urlTargets('a { background: url("x.png") } b { background: url(y.png') // ['x.png', 'y.png']
 */
function urlTargets(css: string): string[] {
  return Array.from(css.matchAll(/url\(\s*/gi), (match) => {
    const start = (match.index ?? 0) + match[0].length
    const quote = css[start] === '"' || css[start] === "'" ? css[start] : undefined
    // Quoted: the string is the target; else the text up to the parenthesis, both as far as the end
    const end = quote === undefined ? css.indexOf(')', start) : css.indexOf(quote, start + 1)
    return css.slice(quote === undefined ? start : start + 1, end === -1 ? css.length : end)
  })
}

/**
 * What a CSS function holds, from just after its opening parenthesis to the one that closes it:
 * nested functions and quoted strings (with their parentheses) included.
 *
 * @param css - CSS text.
 * @param start - Where the function's contents start (after its opening parenthesis).
 * @returns The contents; up to the end of the text when the function is never closed.
 *
 * @example
 * functionContents('image-set(linear-gradient(red, blue) 1x, "a.png" 2x)', 10)
 * // 'linear-gradient(red, blue) 1x, "a.png" 2x'
 */
function functionContents(css: string, start: number): string {
  let depth = 1
  let quote = ''
  for (let index = start; index < css.length; index++) {
    const character = css[index]
    // The text is decoded already (unescapeCss): a backslash in it is a character, never an escape
    if (quote !== '') {
      if (character === quote) quote = ''
    } else if (character === '"' || character === "'") quote = character
    else if (character === '(') depth++
    else if (character === ')' && --depth === 0) return css.slice(start, index)
  }
  return css.slice(start)
}

/**
 * CSS text with its escapes decoded: `\\72` (hexadecimal, up to six digits, one space after it
 * swallowed), `\\l` (any other character as itself), and a backslash before a line break (both
 * removed, as a string continues on the next line).
 *
 * @param written - CSS as written.
 * @returns The same CSS as a browser reads its names and strings.
 *
 * @example
 * unescapeCss('u\\72l(x.png)') // 'url(x.png)'
 */
function unescapeCss(written: string): string {
  // As a browser reads CSS: CRLF, CR and form feed are line feeds before anything else. A backslash
  // before a line feed continues a string on the next line (both go); a hexadecimal escape swallows
  // one whitespace after it
  return written
    .replace(/\r\n|[\r\f]/g, '\n')
    .replace(
      /\\\n|\\([0-9a-fA-F]{1,6})[ \t\n]?|\\([^\n0-9a-fA-F])/g,
      (_written, hexadecimal?: string, character?: string) =>
        hexadecimal
          ? String.fromCodePoint(Math.min(Number.parseInt(hexadecimal, 16), 0x10ffff))
          : (character ?? ''),
    )
}
