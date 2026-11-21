/**
 * Readers for what the Bridge hands the tool rows: a call's `input` and `output` are untyped JSON in
 * which a long text may be a {@link Clipped} and a long list ends with `{ __dwMore: n }`.
 *
 * Why it exists: every tool row reads fields out of those objects, and every one of them has to accept
 * both the whole form and the cut form; reading them here once keeps the row components free of that.
 * Called by the title, result and group code of the tool rows.
 */
import type { Clipped } from '@dw/protocol'

/** A JSON object of unknown content. */
export type Rec = Readonly<Record<string, unknown>>

/** The key of the marker the Bridge puts at the end of a list it cut. */
const MORE_KEY = '__dwMore'

/** What stands in for the items a list lost when the Bridge cut it. */
export type MoreMarker = { __dwMore: number }

/** A text read out of a field, whole or clipped, with the size of the whole. */
export type ReadText = {
  /** The text that is there: the whole of it, or the head of a clipped one. */
  text: string
  /** Lines of the whole text, not counting the one an ending line break closes. */
  lines: number
  /** Characters of the whole text. */
  chars: number
  /** True when the Bridge cut it: the Mirror holds only the head. */
  isClipped: boolean
}

/**
 * Whether a value is a JSON object (not a list, not null).
 *
 * @param value - Anything.
 * @returns True for a plain object.
 */
export function isRecord(value: unknown): value is Rec {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/**
 * Whether a value is the Bridge's {@link Clipped} form of a text.
 *
 * @param value - Anything.
 * @returns True for `{ head, lines, chars }`.
 */
export function isClipped(value: unknown): value is Clipped {
  return (
    isRecord(value) &&
    typeof value['head'] === 'string' &&
    typeof value['lines'] === 'number' &&
    typeof value['chars'] === 'number'
  )
}

/**
 * Whether a value is the marker that ends a list the Bridge cut.
 *
 * @param value - Anything.
 * @returns True for `{ __dwMore: n }`.
 */
export function isMore(value: unknown): value is MoreMarker {
  return isRecord(value) && typeof value[MORE_KEY] === 'number'
}

/**
 * Count the lines of a whole text the way a terminal shows them.
 *
 * @param text - The text.
 * @returns 0 for an empty text; a closing line break does not open another line.
 */
export function countLines(text: string): number {
  if (text === '') return 0
  const parts = text.split('\n')
  return text.endsWith('\n') ? parts.length - 1 : parts.length
}

/**
 * Read a text that may be whole or clipped.
 *
 * @param value - A string, a {@link Clipped}, or anything else.
 * @returns The text with its size, or undefined when the value is neither form.
 */
export function readText(value: unknown): ReadText | undefined {
  if (typeof value === 'string') {
    return { text: value, lines: countLines(value), chars: value.length, isClipped: false }
  }
  if (isClipped(value)) return { text: value.head, lines: value.lines, chars: value.chars, isClipped: true }
  return undefined
}

/**
 * Read a list that may end with the {@link MoreMarker}.
 *
 * @param value - An array, or anything else.
 * @returns The items that are there and how many were left out; empty when the value is no list.
 */
export function readList(value: unknown): { items: unknown[]; more: number } {
  if (!Array.isArray(value)) return { items: [], more: 0 }
  const last: unknown = value.at(-1)
  if (isMore(last)) return { items: value.slice(0, -1), more: last[MORE_KEY] }
  return { items: [...value], more: 0 }
}

/**
 * A field of an object, when the object is one.
 *
 * @param value - Anything.
 * @param key - The field's name.
 * @returns The field's value; undefined when `value` is no object.
 */
export function field(value: unknown, key: string): unknown {
  return isRecord(value) ? value[key] : undefined
}

/**
 * A text field, whole or the head of a clipped one.
 *
 * @param value - An object.
 * @param key - The field's name.
 * @returns The text; undefined when the field is not a text.
 */
export function textField(value: unknown, key: string): string | undefined {
  return readText(field(value, key))?.text
}

/**
 * A number field.
 *
 * @param value - An object.
 * @param key - The field's name.
 * @returns The number; undefined when the field is not a finite number.
 */
export function numberField(value: unknown, key: string): number | undefined {
  const found = field(value, key)
  return typeof found === 'number' && Number.isFinite(found) ? found : undefined
}

/**
 * A boolean field.
 *
 * @param value - An object.
 * @param key - The field's name.
 * @returns True only when the field is exactly `true`.
 */
export function flagField(value: unknown, key: string): boolean {
  return field(value, key) === true
}
