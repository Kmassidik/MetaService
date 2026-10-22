// Reads the error object the Root sends with a refusal. Checks every field; anything of the wrong type is dropped.

/** What the Root says about a refusal. Every field is optional. */
export interface ErrorDetail {
  code?: string
  message?: string
  resource?: string
  needed?: number
  free?: number
}

type Fields = Record<string, unknown>

const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)

/** The text in a field, or nothing when the field is missing or not text. */
const textField = (fields: Fields, key: string): { [name: string]: string } => {
  const value = fields[key]
  return typeof value === 'string' ? { [key]: value } : {}
}

/** The whole number in a field, or nothing when the field is missing or not a whole number. */
const wholeField = (fields: Fields, key: string): { [name: string]: number } => {
  const value = fields[key]
  return typeof value === 'number' && Number.isInteger(value) ? { [key]: value } : {}
}

/** The `error` of an answer body: an object with fields, or (some routes) plain words. Undefined when the body has none. */
export function parseErrorDetail(body: unknown): ErrorDetail | undefined {
  if (!isFields(body)) return undefined
  if (typeof body.error === 'string' && body.error !== '') return { message: body.error }
  if (!isFields(body.error)) return undefined
  const fields = body.error
  return {
    ...textField(fields, 'code'),
    ...textField(fields, 'message'),
    ...textField(fields, 'resource'),
    ...wholeField(fields, 'needed'),
    ...wholeField(fields, 'free'),
  }
}
