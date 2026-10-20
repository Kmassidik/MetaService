// Answers from the API are checked before they are used; nothing is assumed about their shape.
export type Json = Record<string, unknown>

export const isRecord = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value)

/** Reads a reply as an object, or throws saying what the reply was. */
export async function readRecord(reply: Response, what: string): Promise<Json> {
  const body: unknown = await reply.json()
  if (!isRecord(body)) throw new Error(`${what}: the answer is not an object`)
  return body
}

/** One text field of an answer, or a thrown error naming the field. */
export function textField(body: Json, key: string, what: string): string {
  const value = body[key]
  if (typeof value !== 'string' || value === '') throw new Error(`${what}: "${key}" is missing`)
  return value
}

/** The cookie a sign-in reply set, as the `name=value` pair a request sends back. */
export function sessionCookie(reply: Response, what: string): string {
  const header = reply.headers.get('set-cookie')
  const pair = header?.split(';')[0]
  if (!pair) throw new Error(`${what}: no session cookie came back`)
  return pair
}
