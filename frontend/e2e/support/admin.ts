// The operator login the tests use, made and signed in through the API (the browser tests that need the login page do it by hand).
import { readRecord, sessionCookie, textField } from './json.ts'

export const ADMIN = { username: 'admin', password: 'correct horse battery' }

export interface Session {
  cookie: string
  csrf: string
}

/** Headers for a write by a signed-in operator. */
export const writeHeaders = (base: string, session: Session): Record<string, string> =>
  ({ 'Content-Type': 'application/json', Cookie: session.cookie, Origin: base, 'X-CSRF-Token': session.csrf })

const jsonHeaders = (base: string) => ({ 'Content-Type': 'application/json', Origin: base })

/** Signs in as the admin who already exists. */
export async function signIn(base: string): Promise<Session> {
  const reply = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: jsonHeaders(base), body: JSON.stringify(ADMIN) })
  return { cookie: sessionCookie(reply, 'sign in'), csrf: textField(await readRecord(reply, 'sign in'), 'csrf_token', 'sign in') }
}

/** Makes the first admin with the setup token and returns the cookie of the session that came with it. */
export async function createAdmin(base: string, setupToken: string): Promise<string> {
  const reply = await fetch(`${base}/api/auth/setup`, { method: 'POST', headers: jsonHeaders(base), body: JSON.stringify({ ...ADMIN, confirm: ADMIN.password, setup_token: setupToken }) })
  return sessionCookie(reply, 'create the admin')
}
