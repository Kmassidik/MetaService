// The stand-in parent's Security API: GET /api/security/overview and /events answered from a small made-up set (or with 404, like a parent that has no security API yet).
// The log is filtered and paged here the way the real parent will do it (?page=&page_size=, answering { events, total, page, page_size }), so the page's filters
// and page numbers can be tried in a real browser.
import { HEALTHY, HOSTILE_IMG, HOSTILE_NAME, MAC, WARNING } from './data.ts'
import type { Json } from '../support/json.ts'

export const PAGE_SIZE = 50
/** The parent caps page_size here. */
export const MAX_PAGE_SIZE = 100
/** Rows in the big log of the performance check. */
export const BIG_LOG_ROWS = 5000
const BIG_STEP_MS = 60_000
/** Rows of each kind in the stand-in log: 130 in all, so the log needs three pages. */
export const FAILED_ROWS_HEALTHY = 57
/** A Mac's daily SSH connection counts: stored as failed logins with no user and no address. */
export const CONNECTION_ROWS = 3
export const CONNECTION_DETAIL = 'SSH connections (macOS does not log who tried)'
export const CONNECTION_COUNT = 3322
export const FAILED_ROWS_WARNING = 50
export const BLOCK_ROWS = 10
export const LOGIN_ROWS = 10
export const TOTAL_ROWS = FAILED_ROWS_HEALTHY + FAILED_ROWS_WARNING + CONNECTION_ROWS + BLOCK_ROWS + LOGIN_ROWS
export const RANGE_DAYS: Record<string, number> = { '24h': 1, '7d': 7, '30d': 30, '90d': 90 }
/** The one address that only the warning machine sees, to search for. */
export const NEEDLE_ADDRESS = '45.148.10.92'

const HOUR_MS = 3_600_000
const DAY_MS = 24 * HOUR_MS
const STEP_MS = 50 * 60_000

export interface SecurityStandIn {
  /** True: the routes answer 404, like a parent without a security API. */
  missing: boolean
  /** True: the log holds BIG_LOG_ROWS rows, to prove the page draws one page of them. */
  big?: boolean
}

const ago = (ms: number): string => new Date(Date.now() - ms).toISOString()

function bigEvents(): Json[] {
  return Array.from({ length: BIG_LOG_ROWS }, (_, index): Json => ({
    id: `big-${index}`, time: ago(index * BIG_STEP_MS + HOUR_MS), machine: HEALTHY, type: 'failed_login', user: 'ubuntu', address: `10.${index % 250}.${Math.floor(index / 250)}.1`, detail: 'Invalid user', count: 1,
  }))
}

function events(): Json[] {
  const failed = (machine: string, index: number): Json => ({
    id: `f-${machine}-${index}`, time: ago(index * STEP_MS + HOUR_MS), machine, type: 'failed_login', user: machine === WARNING && index % 5 === 0 ? HOSTILE_NAME : 'ubuntu',
    address: machine === WARNING && index === 3 ? NEEDLE_ADDRESS : `185.224.${index % 20}.${index}`, detail: 'Invalid user', count: 100 + index,
  })
  const blocks = Array.from({ length: BLOCK_ROWS }, (_, index): Json => ({ id: `b-${index}`, time: ago(index * 2 * HOUR_MS + 30 * 60_000), machine: HEALTHY, type: 'blocked', user: null, address: `92.118.39.${index}`, detail: 'Blocked after 12 failed tries', count: null }))
  const logins = Array.from({ length: LOGIN_ROWS }, (_, index): Json => ({
    id: `l-${index}`, time: ago(index * 3 * HOUR_MS + 10 * 60_000), machine: index === 2 ? WARNING : MAC, type: 'login', user: index === 2 ? 'deploy' : 'kurnia',
    address: '202.72.223.27', detail: index === 2 ? 'Accepted password' : 'Accepted public key', method: index === 2 ? 'password' : 'key', count: null,
  }))
  const connections = Array.from({ length: CONNECTION_ROWS }, (_, index): Json => ({
    id: `c-${index}`, time: ago(index * 4 * HOUR_MS + 10 * 60_000), machine: MAC, type: 'failed_login', user: null, address: null, detail: CONNECTION_DETAIL, count: CONNECTION_COUNT - index,
  }))
  return [
    ...connections, ...Array.from({ length: FAILED_ROWS_HEALTHY }, (_, index) => failed(HEALTHY, index)), ...Array.from({ length: FAILED_ROWS_WARNING }, (_, index) => failed(WARNING, index)), ...blocks, ...logins,
  ].sort((a, b) => String(b.time).localeCompare(String(a.time)))
}

const baseline = { password_login: false, ban_tool: 'running', firewall: true, auto_updates: true, starts_after_reboot: true, pending_updates: 0 }

function overview(range: string): Json {
  const line = (machine: string, failed: number, extra: Json): Json => ({ machine, reported: true, last_reported: ago(5 * 60_000), baseline, failed, blocked: 3, ...extra })
  const day = (machine: string, back: number, failed: number): Json => ({ day: new Date(Date.now() - back * DAY_MS).toISOString().slice(0, 10), machine, failed })
  return {
    range, generated_at: ago(0),
    machines: [
      line(HEALTHY, 96_000, {}),
      line(WARNING, 33_000, { baseline: { ...baseline, password_login: true, ban_tool: 'not_running', firewall: false, pending_updates: 7 } }),
      line(MAC, CONNECTION_COUNT, { blocked: null, baseline: { ...baseline, ban_tool: 'not_available', starts_after_reboot: null } }),
    ],
    blocked_now: [{ machine: HEALTHY, address: '185.224.128.17', since: ago(2 * HOUR_MS), until: new Date(Date.now() + 22 * HOUR_MS).toISOString(), attempts: 12 }],
    top_users: [{ name: 'ubuntu', count: 31_800 }, { name: HOSTILE_NAME, count: 900 }, { name: HOSTILE_IMG, count: 400 }, { name: 'user', count: 22_400 }],
    top_addresses: [{ name: '185.224.128.17', count: 8_000 }, { name: NEEDLE_ADDRESS, count: 4_000 }],
    daily: [0, 1, 2, 3, 4, 5, 6].flatMap((back) => [day(HEALTHY, back, 12_000 + back * 900), day(WARNING, back, 4_000 + back * 300)]),
  }
}

function eventsPage(query: URLSearchParams, big: boolean): Json {
  const days = RANGE_DAYS[query.get('range') ?? ''] ?? RANGE_DAYS['7d'] ?? 7
  const text = (query.get('q') ?? '').toLowerCase()
  const matching = (big ? bigEvents() : events()).filter((event) => {
    if (Date.parse(String(event.time)) < Date.now() - days * DAY_MS) return false
    if (query.get('machine') && event.machine !== query.get('machine')) return false
    if (query.get('type') && event.type !== query.get('type')) return false
    return text === '' || [event.address, event.user].some((field) => typeof field === 'string' && field.toLowerCase().includes(text))
  })
  const size = Math.min(Math.max(Number(query.get('page_size')) || PAGE_SIZE, 1), MAX_PAGE_SIZE)
  const page = Math.max(Math.floor(Number(query.get('page'))) || 1, 1)
  return { events: matching.slice((page - 1) * size, page * size), total: matching.length, page, page_size: size }
}

/** The routes option of the stand-in parent. */
export function securityRoutes(mode: SecurityStandIn): (path: string, query: URLSearchParams) => { status: number; body: unknown } | null {
  return (path, query) => {
    if (path !== '/api/security/overview' && path !== '/api/security/events') return null
    if (mode.missing) return { status: 404, body: { error: { code: 'not_found', message: 'no such route' } } }
    return { status: 200, body: path.endsWith('/overview') ? overview(query.get('range') ?? '7d') : eventsPage(query, mode.big === true) }
  }
}
