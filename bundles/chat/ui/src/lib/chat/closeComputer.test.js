import { beforeEach, describe, expect, it, vi } from 'vitest'

const api = vi.hoisted(() => vi.fn(async () => ({ state: 'idle' })))

vi.mock('./client.svelte.js', () => ({ api }))
vi.mock('./agents.svelte.js', () => ({ loadAgents: vi.fn() }))
vi.mock('./environment.svelte.js', () => ({
  updateEnvironment: vi.fn(),
  clearComputerWorkspace: vi.fn(),
}))

const { chat } = await import('./state.svelte.js')
const { closeComputer } = await import('./computer.svelte.js')

const BOT = 'bot-1'

beforeEach(() => {
  api.mockClear()
  Object.assign(chat, {
    alive: true,
    session: { csrf: 'csrf' },
    selectedId: BOT,
    connectingApp: null,
    pending: null,
    showComputer: true,
    computers: { [BOT]: { state: 'running' } },
    desktops: { [BOT]: { mode: 'stream', state: 'running', wsPath: `/api/agents/${BOT}/desktop/ws` } },
    computerBusy: {},
    computerErrors: {},
    computerUpdated: {},
    computerText: '',
    computerUrl: '',
  })
})

describe('closeComputer release', () => {
  it('releases on close even when computers state is not takeover (live desktop path)', async () => {
    await closeComputer()

    expect(chat.showComputer).toBe(false)
    expect(api).toHaveBeenCalledWith(
      `/api/agents/${BOT}/computer`,
      expect.objectContaining({ method: 'POST' }),
    )
    expect(JSON.parse(api.mock.calls[0][1].body).action).toBe('release')
  })

  it('skips release while a computer action is in flight', async () => {
    chat.computerBusy = { [BOT]: true }

    await closeComputer()

    expect(chat.showComputer).toBe(false)
    expect(api).not.toHaveBeenCalled()
  })

  it('skips release while a chat turn is pending', async () => {
    chat.pending = { id: BOT }

    await closeComputer()

    expect(api).not.toHaveBeenCalled()
  })
})
