/**
 * Checking functions for what the server sends. An answer is `unknown` until a check says what it
 * is; a check that fails makes a clear error instead of a page that breaks later. Extra fields the
 * check does not name are kept (the screens read them), the named ones are verified.
 */

export type Dict<T> = Record<string, T>

/** A check: true when `value` has the shape `T`. */
export type Check<T> = (value: unknown) => value is T

type OptionalKeys<T> = { [K in keyof T]-?: Record<never, never> extends Pick<T, K> ? K : never }[keyof T]
type RequiredKeys<T> = Exclude<keyof T, OptionalKeys<T>>
type Checks<T, K extends keyof T> = { [P in K]-?: Check<Exclude<T[P], undefined>> }

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export const isString: Check<string> = (value): value is string => typeof value === 'string'
export const isNumber: Check<number> = (value): value is number => typeof value === 'number' && Number.isFinite(value)
export const isBoolean: Check<boolean> = (value): value is boolean => typeof value === 'boolean'
export const isNull: Check<null> = (value): value is null => value === null
/** A field that is present and not checked further (free-form payloads). */
export const anything: Check<unknown> = (value): value is unknown => value !== undefined

export function nullable<T>(check: Check<T>): Check<T | null> {
  return (value): value is T | null => value === null || check(value)
}

export function arrayOf<T>(check: Check<T>): Check<T[]> {
  return (value): value is T[] => Array.isArray(value) && value.every(check)
}

export function dictOf<T>(check: Check<T>): Check<Dict<T>> {
  return (value): value is Dict<T> => isRecord(value) && Object.values(value).every(check)
}

/** An object whose every field is required. */
export function objectOf<T extends object>(required: Checks<T, keyof T>): Check<T> {
  return (value): value is T => isRecord(value) && fieldsPass(required, value, false)
}

/** An object with required fields and optional ones: an optional field may be missing, never `undefined`. */
export function objectWithOptional<T extends object>(
  required: Checks<T, RequiredKeys<T>>,
  optional: Checks<T, OptionalKeys<T>>,
): Check<T> {
  return (value): value is T => isRecord(value) && fieldsPass(required, value, false) && fieldsPass(optional, value, true)
}

function fieldsPass(checks: object, value: Record<string, unknown>, mayBeMissing: boolean): boolean {
  return Object.entries(checks).every(([key, check]) => (mayBeMissing && !(key in value)) || check(value[key]))
}

/** The answer as `T`, or an error that says which answer was wrong. */
export function parseAnswer<T>(check: Check<T>, answer: unknown, what: string): T {
  if (!check(answer)) throw new Error(`The server sent an unexpected ${what} answer. Please reload and try again.`)
  return answer
}
