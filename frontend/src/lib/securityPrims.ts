// The small readers every security parser shares: a value of the wrong type is dropped to null (never to zero or false), text is cleaned and cut short.
// Nothing is trusted: a user name or an address comes from an attacker, so it is only ever a string to show as plain text.
export type Rec = Record<string, unknown>

/** The longest user name or address kept; a longer one is cut and ends with an ellipsis. */
export const MAX_TEXT = 64
/** The longest detail line kept. */
export const MAX_DETAIL = 160
const MAX_DATE_TEXT = 40
const MAX_COUNT = 1_000_000_000_000
const ELLIPSIS = '…'
/** Control characters (including newlines and the escape code) never reach the page. */
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g

export const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)

/** Plain text of at most `limit` characters, or null when nothing is left. */
export function clean(value: unknown, limit: number): string | null {
  if (typeof value !== 'string') return null
  const text = value.replace(CONTROL, ' ').trim()
  if (text === '') return null
  return text.length > limit ? `${text.slice(0, limit - 1)}${ELLIPSIS}` : text
}

export const whole = (value: unknown): number | null => (typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= MAX_COUNT ? value : null)
export const flag = (value: unknown): boolean | null => (typeof value === 'boolean' ? value : null)

/** A date as text the helper gave; only a date that parses is kept. */
export function when(value: unknown): string | null {
  const text = clean(value, MAX_DATE_TEXT)
  return text !== null && !Number.isNaN(Date.parse(text)) ? text : null
}

/** The first `max` items of a list, each read by `read`; items that do not read are left out. A value that is not a list gives an empty list. */
export function rows<T>(value: unknown, read: (item: unknown) => T | null, max: number): T[] {
  if (!Array.isArray(value)) return []
  return value.slice(0, max).map(read).filter((row): row is T => row !== null)
}
