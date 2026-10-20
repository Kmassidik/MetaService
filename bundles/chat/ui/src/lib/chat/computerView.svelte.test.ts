// The big computer view's poll against a scripted server (bug-log #37): a poll that finds the owner
// busy (409), or a reply without a socket path, must never drop a live stream to a snapshot.
import { beforeEach, describe, expect, it, mock } from 'bun:test'
import { session } from '../testFixtures.ts'
import { DeskPhase, deskPhase } from '../../components/workspace/deskStatus.ts'
import { NO_DESKTOP, keptDesktop, nextDesktop } from './desktopState.ts'

const BOT = 'bot-1'
const DESKTOP_PATH = `/api/agents/${BOT}/desktop`
const WS_PATH = `${DESKTOP_PATH}/ws`
const BUSY_POLLS = 3
const LIVE = { state: 'ready', mode: 'stream', wsPath: WS_PATH, display: ':1', message: 'Ubuntu desktop stream is available.' }
const SCREENSHOT = 'data:image/png;base64,' + 'A'.repeat(20000)

const server: { desktop: unknown[], calls: string[] } = { desktop: [], calls: [] }

function busy(): Error {
  return Object.assign(new Error('Wait for your current computer operation to finish.'), { status: 409 })
}

mock.module('./client.svelte.ts', () => ({
  api: mock(async (path: string, options: RequestInit = {}): Promise<unknown> => {
    server.calls.push(`${options.method || 'GET'} ${path}`)
    if (path.endsWith('/desktop')) {
      const next = server.desktop.shift()
      if (next instanceof Error) throw next
      return next
    }
    return { state: 'running', image: SCREENSHOT }
  }),
}))
mock.module('./agents.svelte.ts', () => ({ loadAgents: mock() }))

const { chat } = await import('./state.svelte.ts')
const { refreshComputerView } = await import('./computer.svelte.ts')

const signal = new AbortController().signal
const phase = () => deskPhase({ desktop: chat.desktops[BOT], image: SCREENSHOT, message: '', busy: false })

beforeEach(() => {
  Object.assign(server, { desktop: [], calls: [] })
  Object.assign(chat, { alive: true, session: session(), desktops: {}, computers: {}, computerErrors: {}, computerBusy: {} })
})

describe('polling the open computer view', () => {
  it('keeps a live stream when a later poll finds the owner busy', async () => {
    server.desktop = [LIVE, busy(), busy(), LIVE]
    await refreshComputerView(BOT, { first: true, signal })
    expect(phase()).toBe(DeskPhase.STREAM)
    for (let poll = 0; poll < BUSY_POLLS; poll += 1) {
      await refreshComputerView(BOT, { signal })
      expect(phase()).toBe(DeskPhase.STREAM)
    }
    expect(chat.computerErrors[BOT] || '').toBe('')
  })

  it('goes live after a busy first poll, and stays live (the prod #37 sequence)', async () => {
    server.desktop = [busy(), LIVE, busy()]
    await refreshComputerView(BOT, { first: true, signal })
    expect(chat.desktops[BOT]).toEqual(NO_DESKTOP)
    expect(chat.computerErrors[BOT] || '').toBe('')
    await refreshComputerView(BOT, { signal })
    expect(phase()).toBe(DeskPhase.STREAM)
    await refreshComputerView(BOT, { signal })
    expect(phase()).toBe(DeskPhase.STREAM)
  })

  it('polls only the desktop while it streams: no extra desktop_ensure that could collide', async () => {
    server.desktop = [LIVE, LIVE]
    await refreshComputerView(BOT, { first: true, signal })
    await refreshComputerView(BOT, { signal })
    expect(server.calls).toEqual([`GET ${DESKTOP_PATH}`, `GET ${DESKTOP_PATH}`])
  })

  it('shows the browser while no stream is known, without a busy error', async () => {
    server.desktop = [busy()]
    await refreshComputerView(BOT, { first: true, signal })
    expect(server.calls).toEqual([`GET ${DESKTOP_PATH}`, `GET /api/agents/${BOT}/computer`])
    expect(phase()).toBe(DeskPhase.SNAPSHOT)
  })
})

describe('desktop state merge', () => {
  it('keeps the known socket path when a reply has none (a raw desktop_ensure result)', () => {
    const live = nextDesktop(undefined, LIVE)
    const ensured = nextDesktop(live, { state: 'ready', mode: 'stream', display: ':1', message: '' })
    expect(ensured.wsPath).toBe(WS_PATH)
    expect(deskPhase({ desktop: ensured, image: SCREENSHOT })).toBe(DeskPhase.STREAM)
  })

  it('takes a stream that went down', () => {
    const down = nextDesktop(nextDesktop(undefined, LIVE), { state: 'error', mode: 'stream', wsPath: WS_PATH, message: 'Desktop helper failed' })
    expect(deskPhase({ desktop: down, image: SCREENSHOT })).toBe(DeskPhase.SNAPSHOT)
  })

  it('a failed poll keeps what was known, or nothing', () => {
    const live = nextDesktop(undefined, LIVE)
    expect(keptDesktop(live)).toBe(live)
    expect(keptDesktop(undefined)).toEqual(NO_DESKTOP)
  })
})
