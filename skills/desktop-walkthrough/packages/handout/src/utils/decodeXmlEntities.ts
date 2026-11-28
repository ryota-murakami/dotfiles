/** XML's five named entities and the characters they stand for. */
const NAMED_ENTITIES: Readonly<Record<string, string>> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }

/** The largest Unicode code point: a character reference past it stands for nothing and stays as written. */
const MAX_CODE_POINT = 0x10ffff

/**
 * Decode XML's entities and character references in some text (`&amp;` → `&`, `&#65;` → `A`).
 *
 * Why it exists: a picture's metadata is often XML (XMP), where a signed link's second parameter is
 * written `&amp;signature=`: the secret shapes read it only once decoded, as any XMP reader does.
 * The text is not parsed as XML (metadata sits among binary bytes); only the escapes are decoded.
 * Called by the image check of {@link embedImages} for a raster picture's text.
 *
 * @param text - Text that may hold XML escapes.
 * @returns The same text, its escapes decoded; an escape that names nothing stays as written.
 *
 * @example
 * decodeXmlEntities('a?x=1&amp;signature=0f3a') // 'a?x=1&signature=0f3a'
 * decodeXmlEntities('&#65;&#x42;&bogus;')       // 'AB&bogus;'
 */
export function decodeXmlEntities(text: string): string {
  return text.replace(
    /&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|([a-z]+));/g,
    (written: string, decimal?: string, hexadecimal?: string, name?: string) => {
      const codePoint = decimal ? Number(decimal) : hexadecimal ? Number.parseInt(hexadecimal, 16) : null
      if (codePoint !== null) return codePoint <= MAX_CODE_POINT ? String.fromCodePoint(codePoint) : written
      return NAMED_ENTITIES[name ?? ''] ?? written
    },
  )
}
