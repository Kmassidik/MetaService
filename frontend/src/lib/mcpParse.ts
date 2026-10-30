// The small readers every AI access answer is checked with. Anything that is not the promised shape throws UnreadableAnswer; it is never treated as an empty list.
import { isFields, UnreadableAnswer, type Fields } from './unreadable.ts'

export function fields(value: unknown, what: string): Fields {
  if (!isFields(value)) throw new UnreadableAnswer(`${what} is not an object`)
  return value
}

export function list(raw: unknown, what: string): unknown[] {
  if (!Array.isArray(raw)) throw new UnreadableAnswer(`${what} is not a list`)
  return raw
}

/** A list that arrives bare or inside an object under `key`. */
export function listUnder(raw: unknown, key: string, what: string): unknown[] {
  return list(Array.isArray(raw) ? raw : fields(raw, what)[key], what)
}

export function text(source: Fields, key: string): string {
  const value = source[key]
  if (typeof value !== 'string') throw new UnreadableAnswer(`${key} is not text`)
  return value
}

/** Text that may be missing or null. */
export function maybeText(source: Fields, key: string): string | null {
  const value = source[key]
  if (value === null || value === undefined) return null
  if (typeof value === 'string') return value
  throw new UnreadableAnswer(`${key} is not text`)
}

export function whole(source: Fields, key: string, least: number): number {
  const value = source[key]
  if (typeof value !== 'number' || !Number.isInteger(value) || value < least) throw new UnreadableAnswer(`${key} is not a whole number from ${least}`)
  return value
}

export function maybeWhole(source: Fields, key: string, least: number): number | null {
  if (source[key] === null || source[key] === undefined) return null
  return whole(source, key, least)
}

export function flag(source: Fields, key: string): boolean {
  const value = source[key]
  if (typeof value !== 'boolean') throw new UnreadableAnswer(`${key} is not true or false`)
  return value
}

export function oneOf<T extends string>(value: unknown, allowed: readonly T[], what: string): T {
  const found = allowed.find((word) => word === value)
  if (found === undefined) throw new UnreadableAnswer(`${what} is not one the panel knows`)
  return found
}

const MS_PER_SECOND = 1000

/** A moment as milliseconds. The parent sends an ISO string; a number is read as seconds since 1970. */
function moment(value: unknown, key: string): number {
  if (typeof value === 'number') return value * MS_PER_SECOND
  const ms = typeof value === 'string' ? Date.parse(value) : Number.NaN
  if (!Number.isFinite(ms)) throw new UnreadableAnswer(`${key} is not a time`)
  return ms
}

export const time = (source: Fields, key: string): number => moment(source[key], key)

export function maybeTime(source: Fields, key: string): number | null {
  if (source[key] === null || source[key] === undefined) return null
  return time(source, key)
}
