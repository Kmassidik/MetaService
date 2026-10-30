// The words for every refusal of the Share a PC routes, and the two answers that replace the whole page.
// The hub's status and JSON body come through the parent unchanged, except not_configured (404) and hub_unreachable (502).
import { isFields } from './unreadable.ts'

export const NOT_CONFIGURED_CODE = 'not_configured'
export const HUB_UNREACHABLE_CODE = 'hub_unreachable'
export const WRONG_CODE = 'wrong_code'
const SHARE_PREFIX = '/api/join-share/'

export const NOT_CONFIGURED_TEXT = 'Share a PC is not set up on this parent.'
export const HUB_UNREACHABLE_TEXT = 'The Share a PC hub does not answer. Check that it is running on the parent, then try again.'

const ERROR_TEXT: Record<string, string> = {
  [NOT_CONFIGURED_CODE]: NOT_CONFIGURED_TEXT,
  [HUB_UNREACHABLE_CODE]: HUB_UNREACHABLE_TEXT,
  unauthorized: 'The parent is not allowed into the hub. Check the hub key on the parent.',
  rate_limited: 'Too many tries. Wait a minute and try again.',
  name_taken: 'That name is already used. Choose another name.',
  expired: 'This request has expired. The person has to run a new command.',
  not_pending: 'This request is no longer waiting.',
  unknown_pending: 'This request is gone.',
  unknown_peer: 'This machine is not in the list any more.',
  bad_name: 'The name may only have letters, digits, dot, dash and underscore.',
  bad_share: 'The share numbers must be whole numbers above zero.',
  share_too_high: 'You can lower the share the person offered, not raise it.',
  network_full: 'The WireGuard network has no free address left.',
  wireguard_failed: 'WireGuard on the hub failed. Look at the hub log.',
  locked: 'Too many wrong codes. This request was refused.',
  no_build: 'There is no helper build for this computer yet.',
  windows_soon: 'Windows is coming soon.',
}

export interface ShareFailure {
  /** The hub's error word, or the parent's own when it has no word. */
  code: string
  text: string
}

const triesWord = (count: number) => `${count} ${count === 1 ? 'try' : 'tries'}`

function wrongCodeText(body: Record<string, unknown>): string {
  const left = body.tries_left
  if (typeof left !== 'number' || !Number.isInteger(left) || left < 0) return 'That code is wrong.'
  return `That code is wrong. ${triesWord(left)} left.`
}

function codeOf(body: unknown): string {
  if (!isFields(body)) return ''
  return typeof body.error === 'string' ? body.error : ''
}

/** What went wrong, in plain words, from the status and the body of a refusal. */
export function describeShareError(status: number, body: unknown): ShareFailure {
  const code = codeOf(body)
  if (code === WRONG_CODE && isFields(body)) return { code, text: wrongCodeText(body) }
  const known = ERROR_TEXT[code]
  if (known) return { code, text: known }
  const reason = isFields(body) && typeof body.reason === 'string' ? body.reason : ''
  if (reason) return { code, text: reason }
  return { code, text: `The hub answered with an error (${code || `HTTP ${status}`}).` }
}

/** True for an answer the hub itself gave through the parent (a plain error word). The panel must not retry it: a second try would use up another try of a code. */
export function isHubRefusal(path: string, body: unknown): boolean {
  return path.startsWith(SHARE_PREFIX) && codeOf(body) !== ''
}

export type PageProblem = 'not_configured' | 'hub_unreachable'

/** The two refusals that replace the page. Null for any other failure, which is shown where it happened. */
export function pageProblem(code: string): PageProblem | null {
  if (code === NOT_CONFIGURED_CODE) return NOT_CONFIGURED_CODE
  return code === HUB_UNREACHABLE_CODE ? HUB_UNREACHABLE_CODE : null
}

export const problemText = (problem: PageProblem): string => (problem === NOT_CONFIGURED_CODE ? NOT_CONFIGURED_TEXT : HUB_UNREACHABLE_TEXT)
