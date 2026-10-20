import { beforeEach, describe, expect, it, mock } from 'bun:test'
import { session } from '../testFixtures.ts'

const api = mock(async (_path: string, _options?: RequestInit): Promise<unknown> => ({ state: 'idle' }))

mock.module('./client.svelte.ts', () => ({ api }))
mock.module('./agents.svelte.ts', () => ({ loadAgents: mock() }))
mock.module('./environment.svelte.ts', () => ({
  updateEnvironment: mock(),
  clearComputerWorkspace: mock(),
}))

const { chat } = await import('./state.svelte.ts')
const { closeComputer } = await import('./computer.svelte.ts')

const BOT = 'bot-1'

beforeEach(() => {
  api.mockClear()
  Object.assign(chat, {
    alive: true,
    session: session(),
    selectedId: BOT,
    connectingApp: null,
    pending: null,
    showComputer: true,
    computers: { [BOT]: { state: 'running' } },
    desktops: { [BOT]: { mode: 'stream', state: 'running', wsPath: `/api/agents/${BOT}/desktop/ws`, message: '' } },
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
    const sent = api.mock.calls[0]?.[1]?.body
    expect(JSON.parse(String(sent)).action).toBe('release')
  })

  it('skips release while a computer action is in flight', async () => {
    chat.computerBusy = { [BOT]: true }

    await closeComputer()

    expect(chat.showComputer).toBe(false)
    expect(api).not.toHaveBeenCalled()
  })

  it('skips release while a chat turn is pending', async () => {
    chat.pending = { id: BOT, text: '', attachments: [] }

    await closeComputer()

    expect(api).not.toHaveBeenCalled()
  })
})
