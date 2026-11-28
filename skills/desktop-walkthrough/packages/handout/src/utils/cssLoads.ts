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
 * The text is read a token at a time, as CSS reads it ({@link cssTokens}): an escape is decoded where
 * it stands, so an escaped quote or parenthesis is part of a target and never ends it, and a comment
 * hides nothing.
 *
 * @example
 * cssLoads('fill: url(#gradient); background: image-set("bg.png" 1x)') // ['bg.png']
 * cssLoads('@import "theme.css";')                                     // ['theme.css']
 * cssLoads('background: url("im\\a age.png")')                         // ['image.png']
 */
export function cssLoads(written: string): string[] {
  const tokens = cssTokens(written)
  const urls: string[] = []
  const sets: string[] = []
  const imports: string[] = []
  // Whether each function or parenthesis still open is an image-set: its strings load, also the ones
  // inside a function of its own (an option before a picture may be one, like a gradient)
  const open: boolean[] = []
  tokens.forEach((token, position) => {
    const next = tokens[position + 1]
    switch (token.kind) {
      case 'url':
        urls.push(token.value)
        break
      case 'function':
        // url("…"): the string right after it is the target
        if (token.name === 'url' && next?.kind === 'string') urls.push(next.value)
        open.push(token.name.endsWith('image-set'))
        break
      case 'open':
        open.push(false)
        break
      case 'close':
        open.pop()
        break
      case 'string':
        if (open.includes(true)) sets.push(token.value)
        break
      case 'at':
        // @import's string may follow at once or after comments, which are no tokens
        if (token.name === 'import' && next?.kind === 'string') imports.push(next.value)
        break
      default:
        break
    }
  })
  // As the browser's URL parser reads a target: the control characters and spaces around it go
  // (U+0000 to U+0020, not a no-break space, which stays part of the address), then the tabs and line
  // feeds inside it. `im\a age.png` loads image.png, and `\a #arrow` is the marker #arrow
  return [...urls, ...sets, ...imports]
    .map((target) => withoutEdgeControls(target).replace(/[\t\n\r]/g, ''))
    .filter((target) => target !== '' && !target.startsWith('#'))
}

/**
 * A URL without the control characters and spaces around it (U+0000 to U+0020), which a browser's URL
 * parser drops; a no-break space is none of them and stays. Called by {@link cssLoads}.
 *
 * @param target - A URL as CSS holds it.
 * @returns The URL from its first to its last character above U+0020; '' when it has none.
 *
 * @example
 * withoutEdgeControls('\n picture.png ') // 'picture.png'
 * withoutEdgeControls('\u00a0#arrow')    // '\u00a0#arrow'
 */
function withoutEdgeControls(target: string): string {
  const characters = Array.from(target)
  const first = characters.findIndex((character) => character > ' ')
  if (first === -1) return ''
  return characters.slice(first, characters.findLastIndex((character) => character > ' ') + 1).join('')
}

/**
 * What {@link cssTokens} tells apart in CSS text: a quoted string and an unquoted `url(…)` with their
 * escapes decoded, a function's name (lower case) at its opening parenthesis, an at-keyword's name
 * (lower case), a parenthesis, and anything else. White space and comments are no tokens.
 */
type CssToken =
  | { kind: 'string'; value: string }
  | { kind: 'url'; value: string }
  | { kind: 'function'; name: string }
  | { kind: 'at'; name: string }
  | { kind: 'open' }
  | { kind: 'close' }
  | { kind: 'other' }

/** Whether a character can be part of a CSS name: a letter, a digit, `_`, `-` or anything not ASCII. */
const isNameCharacter = (character: string): boolean => /[\w-]/.test(character) || character >= '\u0080'

/**
 * CSS text as the tokens a browser reads (CSS Syntax 3, as far as loading goes): comments skipped,
 * escapes decoded where they stand (`u\\72l(` is the function `url`, and `"\\22 x"` is a string that
 * starts with a quote), a string ended by its quote, by the end of its line or by the end of the text,
 * and an unquoted `url(…)` read to its closing parenthesis or the end of the text. A string or URL
 * that CSS would call bad is still told, with what it holds so far: a Handout would rather check one
 * target too many. Called by {@link cssLoads}.
 *
 * @param written - CSS as written.
 * @returns Its tokens in order.
 *
 * @example
 * cssTokens('url( "a.png" )') // [{ kind: 'function', name: 'url' }, { kind: 'string', value: 'a.png' }, { kind: 'close' }]
 * cssTokens('url(a\\29 .png)') // [{ kind: 'url', value: 'a).png' }]
 */
function cssTokens(written: string): CssToken[] {
  // As a browser reads CSS: CRLF, CR and form feed are line feeds before anything else
  const css = written.replace(/\r\n|[\r\f]/g, '\n')
  const tokens: CssToken[] = []
  let index = 0
  /** Whether an escape starts at `index`: a backslash followed by anything but a line feed or the end. */
  const atEscape = (): boolean => css[index] === '\\' && index + 1 < css.length && css[index + 1] !== '\n'
  /** Read the escape at `index`: up to six hexadecimal digits and one white space after them, or one character as itself. */
  const escape = (): string => {
    index++
    const hexadecimal = /^[0-9a-fA-F]{1,6}/.exec(css.slice(index, index + 6))?.[0]
    if (hexadecimal === undefined) {
      const character = String.fromCodePoint(css.codePointAt(index) ?? 0xfffd)
      index += character.length
      return character
    }
    index += hexadecimal.length
    if (/[ \t\n]/.test(css[index] ?? '')) index++
    const point = Number.parseInt(hexadecimal, 16)
    // Zero, a surrogate and a number past Unicode's end are the replacement character
    return point === 0 || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)
      ? '�'
      : String.fromCodePoint(point)
  }
  /** Read the name at `index`, its escapes decoded. */
  const name = (): string => {
    let value = ''
    while (index < css.length) {
      if (atEscape()) value += escape()
      else if (isNameCharacter(css[index] ?? '')) value += css[index++]
      else break
    }
    return value
  }
  /** Read the string that opens at `index` with QUOTE: to that quote, the end of the line or the end of the text. */
  const string = (quote: string): string => {
    let value = ''
    index++
    while (index < css.length) {
      const character = css[index] ?? ''
      if (character === quote) {
        index++
        break
      }
      // A line feed that is not escaped ends the string (CSS calls it bad); the line feed stays
      if (character === '\n') break
      if (atEscape()) value += escape()
      // A backslash before a line feed continues the string on the next line; one at the end is nothing
      else if (character === '\\') index += 2
      else value += css[index++]
    }
    return value
  }
  /** Read the unquoted URL at `index` to its closing parenthesis (an escaped one is part of it) or the end. */
  const unquotedUrl = (): string => {
    let value = ''
    while (index < css.length) {
      if (css[index] === ')') {
        index++
        break
      }
      if (atEscape()) value += escape()
      else value += css[index++]
    }
    return value
  }
  while (index < css.length) {
    const character = css[index] ?? ''
    if (css.startsWith('/*', index)) {
      // A comment runs to its end, or to the end of the text: nothing in it is a token
      const end = css.indexOf('*/', index + 2)
      index = end === -1 ? css.length : end + 2
    } else if (character === '"' || character === "'") {
      tokens.push({ kind: 'string', value: string(character) })
    } else if (/\s/.test(character)) {
      index++
    } else if (character === '(' || character === ')') {
      index++
      tokens.push({ kind: character === '(' ? 'open' : 'close' })
    } else if (character === '@') {
      index++
      const keyword = name()
      tokens.push(keyword === '' ? { kind: 'other' } : { kind: 'at', name: keyword.toLowerCase() })
    } else if (isNameCharacter(character) || atEscape()) {
      const word = name().toLowerCase()
      if (css[index] !== '(') {
        tokens.push({ kind: 'other' })
        continue
      }
      index++
      // url( with a quote after optional white space is a function holding a string; else the URL
      // itself follows, unquoted
      // Sticky, from `index`: no copy of the rest of the text for each function
      const afterSpace = /[ \t\n]*["']/y
      afterSpace.lastIndex = index
      const quoted = afterSpace.test(css)
      if (word !== 'url' || quoted) {
        tokens.push({ kind: 'function', name: word })
        continue
      }
      tokens.push({ kind: 'url', value: unquotedUrl() })
    } else {
      index++
      tokens.push({ kind: 'other' })
    }
  }
  return tokens
}
