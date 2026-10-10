// Connect apps against a scripted server: the login probe answers logged_out until the owner
// "finishes signing in", then logged_in. Covers re-check on open, the automatic check while
// signing in, and the re-check after a browser run.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { CONNECT_POLL_LIMIT_MS, RECHECK_AFTER_RUN_MS, connectPollDelay } from '../apps.js'

const server = vi.hoisted(() => ({ probe: {}, checks: [], fail: false }))
const ui = vi.hoisted(() => ({ opened: [], released: 0 }))

vi.mock('./client.svelte.js', () => ({
  api: vi.fn(async (path, options = {}) => {
    if (path === '/api/apps' && !options.method) return { apps: Object.values(server.rows) }
    const { app } = JSON.parse(options.body)
    server.checks.push(app)
    if (server.busy > 0) {
      server.busy -= 1
      throw Object.assign(new Error('Wait for your current computer operation to finish.'), { status: 409 })
    }
    if (server.fail) throw new Error('Your computer could not be reached.')
    const record = { appId: app, connectedAt: 't0', loginState: server.probe[app] || 'logged_out', checkedAt: `t${server.checks.length}` }
    server.rows[app] = record
    return { app: record }
  }),
}))
vi.mock('./computer.svelte.js', () => ({
  ACCOUNT_COMPUTER: 'computer',
  openComputer: vi.fn(async () => {}),
  requestComputer: vi.fn(async (id, action) => {
    if (action === 'release') ui.released += 1
    return { state: 'takeover' }
  }),
}))
vi.mock('./agents.svelte.js', () => ({ closeModal: vi.fn(), openModal: vi.fn(kind => ui.opened.push(kind)) }))
vi.mock('./environment.svelte.js', () => ({ updateEnvironment: vi.fn() }))

const { chat } = await import('./state.svelte.js')
const apps = await import('./apps.svelte.js')

const row = (appId, loginState) => ({ appId, connectedAt: 't0', loginState, checkedAt: 't0' })
const browserRun = [{ kind: 'runtime', payload: { type: 'tool', name: 'browser', phase: 'start' } }]

async function advance(ms) {
  await vi.advanceTimersByTimeAsync(ms)
}

beforeEach(() => {
  vi.useFakeTimers()
  Object.assign(server, { rows: {}, probe: {}, checks: [], fail: false, busy: 0 })
  Object.assign(ui, { opened: [], released: 0 })
  Object.assign(chat, { computerApps: [], appsError: '', connectingApp: null, connectProbeError: '', checkingAppId: '', environment: { state: 'ready' } })
})

afterEach(() => vi.useRealTimers())

describe('re-check when Connect apps opens', () => {
  it('turns an app Connected once the sign-in finished after its last check (the 08:07 bug)', async () => {
    server.rows = { x: row('x', 'logged_out'), google: row('google', 'logged_in') }
    server.probe = { x: 'logged_in' }
    await apps.refreshApps()
    expect(server.checks).toEqual(['x'])
    expect(chat.computerApps.find(app => app.appId === 'x').loginState).toBe('logged_in')
  })

  it('a busy computer is left for the next check, without an error', async () => {
    server.rows = { x: row('x', 'logged_out') }
    server.busy = 1
    await apps.refreshApps()
    expect(server.checks).toEqual(['x'])
    expect(chat.appsError).toBe('')
    expect(chat.computerApps[0].loginState).toBe('logged_out')
  })

  it('does not check on a computer that is not running, and never claims Connected', async () => {
    chat.environment = { state: 'suspended' }
    server.rows = { x: row('x', 'logged_out') }
    server.probe = { x: 'logged_in' }
    await apps.refreshApps()
    expect(server.checks).toEqual([])
    expect(chat.computerApps[0].loginState).toBe('logged_out')
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
    expect(chat.computerApps.find(app => app.appId === 'x').loginState).toBe('logged_in')
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
    expect(chat.computerApps[0].loginState).toBe('logged_out')
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
    apps.recheckAppsAfterRun([{ kind: 'runtime', payload: { type: 'tool', name: 'read', phase: 'start' } }])
    await advance(RECHECK_AFTER_RUN_MS * 2)
    expect(server.checks).toEqual([])
  })
})
