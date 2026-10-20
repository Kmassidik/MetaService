// Connect apps against a scripted server: the login probe answers logged_out until the owner
// "finishes signing in", then logged_in. Covers re-check on open, the automatic check while
// signing in, and the re-check after a browser run.
import { afterEach, beforeEach, describe, expect, it, jest, mock } from 'bun:test'
import { CONNECT_POLL_LIMIT_MS, RECHECK_AFTER_RUN_MS, connectPollDelay } from '../apps.ts'
import { appRecord } from '../testFixtures.ts'
import type { AppRecord, RunEvent } from '../types.ts'

interface ScriptedServer {
  rows: Record<string, AppRecord>
  probe: Record<string, string>
  checks: string[]
  fail: boolean
  busy: number
}

const server: ScriptedServer = { rows: {}, probe: {}, checks: [], fail: false, busy: 0 }
const ui: { opened: string[], released: number } = { opened: [], released: 0 }

mock.module('./client.svelte.ts', () => ({
  api: mock(async (path: string, options: RequestInit = {}): Promise<unknown> => {
    if (path === '/api/apps' && !options.method) return { apps: Object.values(server.rows) }
    const { app } = JSON.parse(String(options.body))
    server.checks.push(app)
    if (server.busy > 0) {
      server.busy -= 1
      throw Object.assign(new Error('Wait for your current computer operation to finish.'), { status: 409 })
    }
    if (server.fail) throw new Error('Your computer could not be reached.')
    const record = appRecord({ appId: app, connectedAt: 't0', loginState: server.probe[app] || 'logged_out', checkedAt: `t${server.checks.length}` })
    server.rows[app] = record
    return { app: record }
  }),
}))
mock.module('./computer.svelte.ts', () => ({
  ACCOUNT_COMPUTER: 'computer',
  openComputer: mock(async () => {}),
  requestComputer: mock(async (_id: string, action: string) => {
    if (action === 'release') ui.released += 1
    return { state: 'takeover' }
  }),
}))
mock.module('./agents.svelte.ts', () => ({ closeModal: mock(), openModal: mock((kind: string) => ui.opened.push(kind)) }))
mock.module('./environment.svelte.ts', () => ({ updateEnvironment: mock() }))

const { chat } = await import('./state.svelte.ts')
const apps = await import('./apps.svelte.ts')

const row = (appId: string, loginState: string): AppRecord => appRecord({ appId, connectedAt: 't0', loginState, checkedAt: 't0' })
const browserRun: RunEvent[] = [{ sequence: 1, createdAt: 't0', kind: 'runtime', payload: { type: 'tool', name: 'browser', phase: 'start' } }]

// Every wait in these tests is a whole multiple of this many ms, so stepping by it fires each timer on time.
const COARSE_STEP_MS = 125
const FINE_ADVANCE_MAX_MS = 30000
const MICROTASK_TURNS = 25

async function settle(): Promise<void> {
  for (let turn = 0; turn < MICROTASK_TURNS; turn += 1) await Promise.resolve()
}

/** Moves the fake clock on, letting the code under test finish its awaits after every timer. */
async function advance(ms: number): Promise<void> {
  const step = ms <= FINE_ADVANCE_MAX_MS ? 1 : COARSE_STEP_MS
  for (let left = ms; left > 0; left -= step) {
    jest.advanceTimersByTime(Math.min(step, left))
    await settle()
  }
}

beforeEach(() => {
  jest.useFakeTimers()
  Object.assign(server, { rows: {}, probe: {}, checks: [], fail: false, busy: 0 })
  Object.assign(ui, { opened: [], released: 0 })
  Object.assign(chat, { computerApps: [], appsError: '', connectingApp: null, connectProbeError: '', checkingAppId: '', environment: { state: 'ready' } })
})

afterEach(() => jest.useRealTimers())

describe('re-check when Connect apps opens', () => {
  it('turns an app Connected once the sign-in finished after its last check (the 08:07 bug)', async () => {
    server.rows = { x: row('x', 'logged_out'), google: row('google', 'logged_in') }
    server.probe = { x: 'logged_in' }
    await apps.refreshApps()
    expect(server.checks).toEqual(['x'])
    expect(chat.computerApps.find(app => app.appId === 'x')?.loginState).toBe('logged_in')
  })

  it('a busy computer is left for the next check, without an error', async () => {
    server.rows = { x: row('x', 'logged_out') }
    server.busy = 1
    await apps.refreshApps()
    expect(server.checks).toEqual(['x'])
    expect(chat.appsError).toBe('')
    expect(chat.computerApps[0]?.loginState).toBe('logged_out')
  })

  it('does not check on a computer that is not running, and never claims Connected', async () => {
    chat.environment = { state: 'suspended' }
    server.rows = { x: row('x', 'logged_out') }
    server.probe = { x: 'logged_in' }
    await apps.refreshApps()
    expect(server.checks).toEqual([])
    expect(chat.computerApps[0]?.loginState).toBe('logged_out')
  })

  it('a failed check keeps the last answer, shows the error and still checks the others', async () => {
    server.rows = { x: row('x', 'logged_out'), google: row('google', 'unknown') }
    server.fail = true
    await apps.refreshApps()
    expect(server.checks).toEqual(['x', 'google'])
    expect(chat.appsError).toMatch(/could not be reached/)
    expect(chat.computerApps.every(app => app.loginState !== 'logged_in')).toBe(true)
  })
})

describe('checking on its own while the owner signs in', () => {
  it('turns Connected without a tap, gives the screen back and shows Connect apps', async () => {
    await apps.connectApp('x')
    expect(chat.connectingApp?.id).toBe('x')
    await advance(connectPollDelay(0))
    expect(server.checks).toEqual(['x'])
    expect(chat.connectingApp?.id).toBe('x')
    server.probe.x = 'logged_in'                               // the owner finished signing in
    await advance(connectPollDelay(1))
    expect(server.checks).toEqual(['x', 'x'])
    expect(chat.computerApps.find(app => app.appId === 'x')?.loginState).toBe('logged_in')
    expect(chat.connectingApp).toBe(null)
    expect(ui.released).toBe(1)
    expect(ui.opened).toEqual(['marketplace'])
    await advance(CONNECT_POLL_LIMIT_MS)
    expect(server.checks.length).toBe(2)
  })

  it('stops checking when the owner cancels', async () => {
    await apps.connectApp('google')
    await advance(connectPollDelay(0))
    await apps.cancelAppConnect()
    await advance(CONNECT_POLL_LIMIT_MS)
    expect(server.checks).toEqual(['google'])
    expect(ui.opened).toEqual([])
  })

  it('gives up after the limit, never marking the app Connected', async () => {
    await apps.connectApp('x')
    await advance(CONNECT_POLL_LIMIT_MS * 2)
    const checks = server.checks.length
    expect(checks).toBeGreaterThan(5)
    await advance(CONNECT_POLL_LIMIT_MS)
    expect(server.checks.length).toBe(checks)
    expect(chat.connectingApp?.id).toBe('x')
    expect(chat.computerApps[0]?.loginState).toBe('logged_out')
  })

  it('keeps checking through a busy computer (the screen preview holds it) and still connects', async () => {
    server.busy = 2
    server.probe.x = 'logged_in'
    await apps.connectApp('x')
    await advance(connectPollDelay(0) + connectPollDelay(1) + connectPollDelay(2))
    expect(server.checks).toEqual(['x', 'x', 'x'])
    expect(chat.connectProbeError).toBe('')
    expect(chat.connectingApp).toBe(null)
    expect(ui.opened).toEqual(['marketplace'])
  })

  it('stops and shows the error when a check fails', async () => {
    server.fail = true
    await apps.connectApp('x')
    await advance(CONNECT_POLL_LIMIT_MS)
    expect(server.checks).toEqual(['x'])
    expect(chat.connectProbeError).toMatch(/could not be reached/)
  })
})

describe('re-check after a bot run', () => {
  it('checks every app on record once, after runs that used the browser settle', async () => {
    server.rows = { x: row('x', 'logged_in'), google: row('google', 'logged_out') }
    chat.computerApps = Object.values(server.rows)
    apps.recheckAppsAfterRun(browserRun)
    await advance(RECHECK_AFTER_RUN_MS / 2)
    apps.recheckAppsAfterRun(browserRun)                         // a second run restarts the wait
    await advance(RECHECK_AFTER_RUN_MS - 1)
    expect(server.checks).toEqual([])
    await advance(1)
    expect(server.checks.sort()).toEqual(['google', 'x'])
  })

  it('does nothing after a run without the browser', async () => {
    chat.computerApps = [row('x', 'logged_out')]
    apps.recheckAppsAfterRun([{ sequence: 1, createdAt: 't0', kind: 'runtime', payload: { type: 'tool', name: 'read', phase: 'start' } }])
    await advance(RECHECK_AFTER_RUN_MS * 2)
    expect(server.checks).toEqual([])
  })
})
