import { describe, expect, it } from 'vitest'
import {
  AppState,
  CONNECT_POLL_BACKOFF,
  CONNECT_POLL_FIRST_MS,
  CONNECT_POLL_LIMIT_MS,
  CONNECT_POLL_MAX_MS,
  appState,
  appStateLabel,
  appsAfterRun,
  appsToRecheck,
  connectPollDelay,
  connectedAppList,
  isConnected,
  keepPolling,
  notSignedInMessage,
  offeredApps,
  runUsedBrowser,
} from './apps.js'

const app = (appId, loginState, checkedAt = '2026-10-01T08:00:00Z') => ({ appId, loginState, connectedAt: '2026-10-01T07:00:00Z', checkedAt })

describe('Connected only after the login check', () => {
  it('is Connected only when the probe said logged_in', () => {
    expect(isConnected(app('x', 'logged_in'))).toBe(true)
    expect(isConnected(app('x', 'unknown'))).toBe(false)
    expect(isConnected(app('x', 'logged_out'))).toBe(false)
    expect(isConnected({ appId: 'x', loginState: 'yes' })).toBe(false)
  })

  it('shows Checking… for the app being checked, whatever it was before', () => {
    expect(appState(app('x', 'logged_in'), 'x', 'x')).toBe(AppState.CHECKING)
    expect(appState(null, 'x', 'x')).toBe(AppState.CHECKING)
    expect(appState(app('x', 'logged_in'), 'x', 'github')).toBe(AppState.CONNECTED)
  })

  it('offers Connect for an app never connected and a check for one not signed in', () => {
    expect(appState(null, 'x')).toBe(AppState.NOT_CONNECTED)
    expect(appState(app('x', 'logged_out'), 'x')).toBe(AppState.NEEDS_CHECK)
    expect(appState(app('x', 'unknown'), 'x')).toBe(AppState.NEEDS_CHECK)
  })

  it('says when an app was never checked', () => {
    expect(appStateLabel(AppState.NEEDS_CHECK, app('x', 'unknown', null))).toBe('Not checked yet')
    expect(appStateLabel(AppState.NEEDS_CHECK, app('x', 'logged_out'))).toBe('Not signed in')
    expect(appStateLabel(AppState.CONNECTED, app('x', 'logged_in'))).toBe('Connected')
  })

  it('explains a failed check without claiming a connection', () => {
    expect(notSignedInMessage('X', app('x', 'logged_out'))).toMatch(/isn’t signed in yet/)
    expect(notSignedInMessage('Gmail', app('gmail', 'unknown'))).toMatch(/couldn’t confirm/)
  })
})

describe('re-check when Connect apps opens', () => {
  const ready = { state: 'ready' }

  it('re-checks every app not signed in, even one checked before (the 08:07 logged_out bug)', () => {
    const apps = [app('x', 'logged_out', '2026-10-01T08:07:23Z'), app('google', 'unknown', null), app('github', 'logged_in')]
    expect(appsToRecheck(apps, ready)).toEqual(['x', 'google'])
  })

  it('never re-checks an app already signed in, or on a computer that is not running', () => {
    const apps = [app('x', 'logged_in'), app('google', 'logged_out')]
    expect(appsToRecheck(apps, ready)).toEqual(['google'])
    expect(appsToRecheck(apps, { state: 'suspended' })).toEqual([])
    expect(appsToRecheck(apps, { state: 'provisioning' })).toEqual([])
    expect(appsToRecheck(apps, null)).toEqual([])
  })

  it('skips apps Connect apps does not offer', () => {
    const apps = [app('x', 'logged_out'), app('discord', 'unknown')]
    expect(appsToRecheck(apps, ready, id => id === 'x')).toEqual(['x'])
    expect(offeredApps(apps, id => id === 'x').map(item => item.appId)).toEqual(['x'])
  })
})

describe('checking on its own while the owner signs in', () => {
  it('backs off from the first wait up to the longest one', () => {
    const delays = [0, 1, 2, 3, 4, 5, 10].map(connectPollDelay)
    expect(delays[0]).toBe(CONNECT_POLL_FIRST_MS)
    expect(delays[1]).toBe(CONNECT_POLL_FIRST_MS * CONNECT_POLL_BACKOFF)
    expect(delays.every((delay, index) => index === 0 || delay >= delays[index - 1])).toBe(true)
    expect(Math.max(...delays)).toBe(CONNECT_POLL_MAX_MS)
  })

  it('stops when the flow closes, the sign-in is seen, or the limit passes', () => {
    expect(keepPolling({ open: true, connected: false, elapsedMs: 0 })).toBe(true)
    expect(keepPolling({ open: false, connected: false, elapsedMs: 0 })).toBe(false)
    expect(keepPolling({ open: true, connected: true, elapsedMs: 0 })).toBe(false)
    expect(keepPolling({ open: true, connected: false, elapsedMs: CONNECT_POLL_LIMIT_MS })).toBe(false)
  })

  it('checks a bounded number of times before giving up', () => {
    let elapsed = 0
    let checks = 0
    while (keepPolling({ open: true, connected: false, elapsedMs: elapsed })) elapsed += connectPollDelay(checks++)
    expect(checks).toBeGreaterThan(5)
    expect(checks).toBeLessThan(CONNECT_POLL_LIMIT_MS / CONNECT_POLL_FIRST_MS)
  })
})

describe('re-check after a bot run', () => {
  const tool = name => ({ kind: 'runtime', payload: { type: 'tool', name, phase: 'start' } })

  it('only after a run that used the browser or the screen', () => {
    expect(runUsedBrowser([tool('read'), tool('browser')])).toBe(true)
    expect(runUsedBrowser([tool('ruvio_desktop')])).toBe(true)
    expect(runUsedBrowser([tool('read'), tool('exec')])).toBe(false)
    expect(runUsedBrowser([{ kind: 'approval.requested', payload: { name: 'browser' } }])).toBe(false)
    expect(runUsedBrowser(undefined)).toBe(false)
  })

  it('checks every offered app on record, signed in or not, on a running computer', () => {
    const apps = [app('x', 'logged_in'), app('google', 'logged_out'), app('slack', 'unknown')]
    expect(appsAfterRun(apps, { state: 'ready' }, id => id !== 'slack')).toEqual(['x', 'google'])
    expect(appsAfterRun(apps, { state: 'suspended' })).toEqual([])
  })
})

describe('connected app list', () => {
  it('lists signed-in apps with their names', () => {
    const apps = [app('x', 'logged_in'), app('gmail', 'unknown'), app('github', 'logged_in')]
    expect(connectedAppList(apps, id => id.toUpperCase())).toEqual([{ id: 'x', name: 'X' }, { id: 'github', name: 'GITHUB' }])
  })
})
