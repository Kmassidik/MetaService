/** An answer from the parent that is not shaped the way the panel expects. The text says what was wrong. */
export class UnreadableAnswer extends Error {}

export type Fields = Record<string, unknown>

export const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)

/** The text in a field, null when it is missing or null; anything else is unreadable. */
export function optionalText(source: Fields, key: string): string | null {
  const value = source[key]
  if (value === null || value === undefined) return null
  if (typeof value === 'string') return value
  throw new UnreadableAnswer(`${key} is not text`)
}
