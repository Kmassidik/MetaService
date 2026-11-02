// SAMPLE DATA ONLY. Everything in this file is made up to show the Security page before the parent collects anything. Nothing here is real, and nothing outside the
// sample-data preview (#/security?preview=1) may import this file: the real data path (securityApi.ts, securityParse.ts) never does. The numbers are modelled on what
// the real machines see: about 96,000 failed logins in 17 days on the RTX PC from 24 addresses, about 33,000 on the DGX Spark from 38, the same few user names.
import { bucketRows, type MockBucket } from './securityMockBuckets.ts'
import type { BlockedNowRow, SecurityEvent } from './securityTypes.ts'
import type { SecurityBaseline } from './types.ts'

export interface MockMachine {
  id: string
  name: string
  state: 'online' | 'busy' | 'offline'
  os: 'macos' | 'linux'
  /** False for the machine that has never reported: it has no line in the overview. */
  reports: boolean
  baseline: SecurityBaseline
}

export interface MockStore {
  machines: MockMachine[]
  events: SecurityEvent[]
  blocked_now: BlockedNowRow[]
  /** Ten-minute counts of the last 24 hours, for the ranges up to 24 h. */
  buckets: MockBucket[]
}

const HOUR_MS = 3_600_000
const DAY_MS = 24 * HOUR_MS
const DAYS_OF_NOISE = 17
const RTX_FAILED = 96_000
const RTX_ADDRESSES = 24
const SPARK_FAILED = 33_000
const SPARK_ADDRESSES = 38
const STUDIO_CONNECTIONS_MIN = 2_800
const STUDIO_CONNECTIONS_SPREAD = 900
const BLOCK_LASTS_MS = DAY_MS
const OWNER_ADDRESS = '202.72.223.27'
const KEY_LOGIN_ADDRESSES = [OWNER_ADDRESS, '198.51.100.23', '203.0.113.88']
const PASSWORD_LOGIN_ADDRESS = '203.0.113.200'
const SEED = 20261101
const BOT_USERS: readonly (readonly [string, number])[] = [['ubuntu', 33], ['user', 23], ['test', 15], ['admin', 12], ['postgres', 8], ['root', 5], ['oracle', 2], ['git', 2]]
const ADDRESS_PREFIXES = ['185.224', '45.148', '92.118', '193.32', '141.98', '80.94', '178.128', '206.189']
const FAVOURITE_STAYS = 0.7
const RTX_PER_BUCKET = 40
const SPARK_PER_BUCKET = 14
const STUDIO_PER_BUCKET = 22
const STUDIO_ADDRESSES: string[] = []

const key = { password_login: false, ban_tool: 'running', firewall: true, auto_updates: true, starts_after_reboot: true, pending_updates: 0 } as const

const MACHINES: MockMachine[] = [
  { id: 'mac-studio', name: 'Mac Studio', state: 'online', os: 'macos', reports: true, baseline: { ...key, ban_tool: 'not_available' } },
  { id: 'mac-mini', name: 'Mac Mini', state: 'online', os: 'macos', reports: false, baseline: { ...key } },
  { id: 'dgx-spark', name: 'DGX Spark', state: 'online', os: 'linux', reports: true, baseline: { ...key, password_login: true, pending_updates: 4 } },
  { id: 'rtx-5090-pc', name: 'RTX 5090 PC', state: 'online', os: 'linux', reports: true, baseline: { ...key, auto_updates: false, pending_updates: 2 } },
]

/** A small repeatable random number generator: the same sample every time, so a picture and a test never drift. */
function random(seed: number): () => number {
  let state = seed
  return () => {
    state = (state + 0x6d2b79f5) | 0
    let mixed = Math.imul(state ^ (state >>> 15), 1 | state)
    mixed = (mixed + Math.imul(mixed ^ (mixed >>> 7), 61 | mixed)) ^ mixed
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296
  }
}

type Random = () => number

function pick<T>(list: readonly T[], next: Random): T {
  const item = list[Math.floor(next() * list.length)]
  if (item === undefined) throw new Error('the sample data picked from an empty list')
  return item
}

function botUser(next: Random): string {
  const total = BOT_USERS.reduce((sum, [, weight]) => sum + weight, 0)
  let ticket = next() * total
  for (const [name, weight] of BOT_USERS) {
    ticket -= weight
    if (ticket < 0) return name
  }
  return 'root'
}

function botAddresses(count: number, next: Random): string[] {
  const made = new Set<string>()
  while (made.size < count) made.add(`${pick(ADDRESS_PREFIXES, next)}.${Math.floor(next() * 250) + 1}.${Math.floor(next() * 250) + 1}`)
  return [...made]
}

interface Attacker {
  address: string
  user: string
  weight: number
}

/** One day's failed-login row for one attacker, stored as a daily count like the real database will. */
function failedRows(machine: string, total: number, addresses: string[], now: number, next: Random): SecurityEvent[] {
  const attackers: Attacker[] = addresses.map((address) => ({ address, user: botUser(next), weight: 0.3 + next() * 1.4 }))
  const todayStart = Math.floor(now / DAY_MS) * DAY_MS
  const cells = Array.from({ length: DAYS_OF_NOISE }, (_, ago) => attackers.map((attacker) => ({ attacker, ago, share: attacker.weight * (0.4 + next()) * (ago === 5 ? 3 : 1) })))
  const scale = total / cells.flat().reduce((sum, cell) => sum + cell.share, 0)
  return cells.flat().map((cell, index) => {
    const dayStart = todayStart - cell.ago * DAY_MS
    const time = dayStart + next() * Math.min(DAY_MS, now - dayStart - 1)
    const user = next() < FAVOURITE_STAYS ? cell.attacker.user : botUser(next)
    return { id: `failed-${machine}-${index}`, time: new Date(time).toISOString(), machine, type: 'failed_login', user, address: cell.attacker.address, detail: 'Invalid user, password refused', method: null, count: Math.max(1, Math.round(cell.share * scale)) }
  })
}

/** A Mac cannot say who connected, so the parent stores one count of SSH connections for each day, with no user and no address. */
function connectionRows(machine: string, now: number, next: Random): SecurityEvent[] {
  const todayStart = Math.floor(now / DAY_MS) * DAY_MS
  return Array.from({ length: DAYS_OF_NOISE }, (_, ago) => {
    const dayStart = todayStart - ago * DAY_MS
    const time = dayStart + next() * Math.min(DAY_MS, now - dayStart - 1)
    const count = STUDIO_CONNECTIONS_MIN + Math.floor(next() * STUDIO_CONNECTIONS_SPREAD)
    return { id: `connections-${machine}-${ago}`, time: new Date(time).toISOString(), machine, type: 'failed_login' as const, user: null, address: null, detail: null, method: null, count }
  })
}

/** An address is blocked after failing too often and let go a day later. */
function blockEvents(machine: string, addresses: string[], now: number, next: Random): { events: SecurityEvent[]; stillBlocked: BlockedNowRow[] } {
  const events: SecurityEvent[] = []
  const stillBlocked: BlockedNowRow[] = []
  addresses.forEach((address, index) => {
    const since = now - next() * DAYS_OF_NOISE * DAY_MS
    const until = since + BLOCK_LASTS_MS
    const attempts = 6 + Math.floor(next() * 40)
    events.push({ id: `blocked-${machine}-${index}`, time: new Date(since).toISOString(), machine, type: 'blocked', user: null, address, detail: `Blocked after ${attempts} failed tries`, method: null, count: null })
    if (until > now) stillBlocked.push({ machine, address, since: new Date(since).toISOString(), until: new Date(until).toISOString(), attempts })
    else events.push({ id: `unblocked-${machine}-${index}`, time: new Date(until).toISOString(), machine, type: 'unblocked', user: null, address, detail: 'Block ended', method: null, count: null })
  })
  return { events, stillBlocked }
}

function loginEvents(machine: string, perDay: number, now: number, next: Random, viaPassword = false): SecurityEvent[] {
  return Array.from({ length: DAYS_OF_NOISE * perDay }, (_, index) => {
    const password = viaPassword && index % 6 === 0
    return {
      id: `login-${machine}-${index}`, time: new Date(now - next() * DAYS_OF_NOISE * DAY_MS).toISOString(), machine, type: 'login' as const,
      user: password ? 'deploy' : pick(['kurnia', 'luca'], next), address: password ? PASSWORD_LOGIN_ADDRESS : pick(KEY_LOGIN_ADDRESSES, next),
      detail: password ? 'Accepted password' : 'Accepted public key', method: password ? ('password' as const) : ('key' as const), count: null,
    }
  })
}

/** The whole sample, made fresh for `now`. */
export function buildMockStore(now: number): MockStore {
  const next = random(SEED)
  const rtx = botAddresses(RTX_ADDRESSES, next)
  const spark = botAddresses(SPARK_ADDRESSES, next)
  const rtxBlocks = blockEvents('rtx-5090-pc', rtx, now, next)
  const sparkBlocks = blockEvents('dgx-spark', spark, now, next)
  const events = [
    ...failedRows('rtx-5090-pc', RTX_FAILED, rtx, now, next), ...failedRows('dgx-spark', SPARK_FAILED, spark, now, next), ...connectionRows('mac-studio', now, next),
    ...rtxBlocks.events, ...sparkBlocks.events,
    ...loginEvents('mac-studio', 3, now, next), ...loginEvents('rtx-5090-pc', 1, now, next), ...loginEvents('dgx-spark', 1, now, next, true),
  ]
  const buckets = [
    ...bucketRows({ machine: 'rtx-5090-pc', perBucket: RTX_PER_BUCKET, addresses: rtx, user: botUser }, now, next),
    ...bucketRows({ machine: 'dgx-spark', perBucket: SPARK_PER_BUCKET, addresses: spark, user: botUser }, now, next),
    ...bucketRows({ machine: 'mac-studio', perBucket: STUDIO_PER_BUCKET, addresses: STUDIO_ADDRESSES, user: null }, now, next),
  ]
  return { machines: MACHINES, events, blocked_now: [...rtxBlocks.stillBlocked, ...sparkBlocks.stillBlocked], buckets }
}
