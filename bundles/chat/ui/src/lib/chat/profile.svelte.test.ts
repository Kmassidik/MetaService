// Details Save feedback and the unsaved-changes guard, against a scripted PATCH /api/agents/:id.
import { afterEach, beforeEach, describe, expect, it, jest, mock } from 'bun:test'
import { SAVED_FLASH_MS } from '../savedFlash.ts'
import { agent, session } from '../testFixtures.ts'

const server: { patches: Record<string, unknown>[], fail: boolean } = { patches: [], fail: false }

mock.module('./client.svelte.ts', () => ({
  api: mock(async (path: string, options: RequestInit = {}): Promise<unknown> => {
    if (options.method !== 'PATCH') return {}
    if (server.fail) throw new Error('Could not save.')
    const body = JSON.parse(String(options.body))
    server.patches.push(body)
    return { agent: agent({ ...body, id: decodeURIComponent(path.split('/').pop() ?? '') }) }
  }),
}))
mock.module('./agents.svelte.ts', () => ({ patchRoster: mock(async () => {}) }))
mock.module('./sidePanel.svelte.ts', () => ({ openSidePanel: mock(async () => {}) }))

const { chat } = await import('./state.svelte.ts')
const profile = await import('./profile.svelte.ts')
const guard = await import('./unsavedGuard.svelte.ts')

const saved = agent({ id: 'b1', name: 'Atlas', title: '', summary: 'Plans trips', description: 'Be brief.' })

// Lets the code under test finish its awaits after a timer fires.
async function advance(ms: number): Promise<void> {
  jest.advanceTimersByTime(ms)
  for (let turn = 0; turn < 10; turn += 1) await Promise.resolve()
}

const leaveSpy = () => mock<() => void>(() => undefined)

beforeEach(() => {
  jest.useFakeTimers()
  Object.assign(server, { patches: [], fail: false })
  Object.assign(chat, {
    alive: true, session: session({ csrf: 'k' }), pending: null, agents: [{ ...saved }], selectedId: saved.id, sidePanelOpen: true,
    profileSaving: false, profileError: '', profileSaved: {}, unsavedPrompt: false,
    profileName: 'Atlas', profileTitle: '', profileSummary: 'Plans trips', profileInstructions: 'Be brief.',
  })
  guard.dropLeave()
})

afterEach(() => jest.useRealTimers())

describe('Save in Details', () => {
  it('shows Saved for SAVED_FLASH_MS after a successful save, and the form is clean again', async () => {
    chat.profileName = 'Atlas Prime '
    expect(guard.profileDirty()).toBe(true)
    expect(await profile.saveProfile()).toBe(true)
    expect(server.patches[0]?.name).toBe('Atlas Prime')
    expect(chat.agents[0]?.name).toBe('Atlas Prime')
    expect(guard.profileDirty()).toBe(false)
    expect(chat.profileSaved.details).toBe(true)
    await advance(SAVED_FLASH_MS)
    expect(chat.profileSaved.details).toBe(false)
  })

  it('keeps the error box (and no tick) when the save fails', async () => {
    server.fail = true
    chat.profileName = 'Atlas Prime'
    expect(await profile.saveProfile()).toBe(false)
    expect(chat.profileError).toBe('Could not save.')
    expect(chat.profileSaved.details).toBeFalsy()
    expect(chat.profileSaving).toBe(false)
  })

  it('ticks the label after it saves', async () => {
    await profile.saveTitle(' Travel ')
    expect(chat.profileTitle).toBe('Travel')
    expect(chat.profileSaved.label).toBe(true)
    await advance(SAVED_FLASH_MS)
    expect(chat.profileSaved.label).toBe(false)
  })

  it('ticks an instant setting (avatar) after it saves', async () => {
    await profile.patchProfileSetting(profile.SAVED_TICK.avatar, { avatarColor: '#3B82F6' })
    expect(chat.profileSaved.avatar).toBe(true)
  })
})

describe('unsaved changes guard', () => {
  it('leaves at once when there is nothing unsaved', () => {
    const leave = leaveSpy()
    guard.guardUnsaved(leave)
    expect(leave).toHaveBeenCalledTimes(1)
    expect(chat.unsavedPrompt).toBe(false)
  })

  it('holds the leave and asks while Details has edits', () => {
    const leave = leaveSpy()
    chat.profileSummary = 'Plans trips and hotels'
    guard.guardUnsaved(leave)
    expect(leave).not.toHaveBeenCalled()
    expect(chat.unsavedPrompt).toBe(true)
  })

  it('Discard restores the saved profile, then leaves', () => {
    const leave = leaveSpy()
    chat.profileInstructions = 'Be thorough.'
    guard.guardUnsaved(leave)
    profile.discardAndLeave()
    expect(chat.profileInstructions).toBe('Be brief.')
    expect(leave).toHaveBeenCalledTimes(1)
    expect(chat.unsavedPrompt).toBe(false)
    expect(server.patches).toEqual([])
  })

  it('Save saves first, then leaves', async () => {
    const leave = leaveSpy()
    chat.profileName = 'Atlas Prime'
    guard.guardUnsaved(leave)
    await profile.saveAndLeave()
    expect(server.patches).toHaveLength(1)
    expect(leave).toHaveBeenCalledTimes(1)
    expect(chat.unsavedPrompt).toBe(false)
  })

  it('Save that fails stays, with the prompt still up', async () => {
    const leave = leaveSpy()
    server.fail = true
    chat.profileName = 'Atlas Prime'
    guard.guardUnsaved(leave)
    await profile.saveAndLeave()
    expect(leave).not.toHaveBeenCalled()
    expect(chat.unsavedPrompt).toBe(true)
    expect(chat.profileError).toBe('Could not save.')
  })

  it('does not ask while the panel is closed', () => {
    const leave = leaveSpy()
    chat.sidePanelOpen = false
    chat.profileName = 'Atlas Prime'
    guard.guardUnsaved(leave)
    expect(leave).toHaveBeenCalledTimes(1)
  })
})
