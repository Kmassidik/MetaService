// Details Save feedback and the unsaved-changes guard, against a scripted PATCH /api/agents/:id.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { SAVED_FLASH_MS } from '../savedFlash.js'

const server = vi.hoisted(() => ({ patches: [], fail: false }))

vi.mock('./client.svelte.js', () => ({
  api: vi.fn(async (path, options = {}) => {
    if (options.method !== 'PATCH') return {}
    if (server.fail) throw new Error('Could not save.')
    const body = JSON.parse(options.body)
    server.patches.push(body)
    return { agent: { id: decodeURIComponent(path.split('/').pop()), ...body } }
  }),
}))
vi.mock('./agents.svelte.js', () => ({ patchRoster: vi.fn(async () => {}) }))
vi.mock('./sidePanel.svelte.js', () => ({ openSidePanel: vi.fn(async () => {}) }))

const { chat } = await import('./state.svelte.js')
const profile = await import('./profile.svelte.js')
const guard = await import('./unsavedGuard.svelte.js')

const saved = { id: 'b1', kind: 'bot', name: 'Atlas', title: '', summary: 'Plans trips', description: 'Be brief.' }

beforeEach(() => {
  vi.useFakeTimers()
  Object.assign(server, { patches: [], fail: false })
  Object.assign(chat, {
    alive: true, session: { csrf: 'k' }, pending: null, agents: [{ ...saved }], selectedId: saved.id, sidePanelOpen: true,
    profileSaving: false, profileError: '', profileSaved: {}, unsavedPrompt: false,
    profileName: 'Atlas', profileTitle: '', profileSummary: 'Plans trips', profileInstructions: 'Be brief.',
  })
  guard.dropLeave()
})

afterEach(() => vi.useRealTimers())

describe('Save in Details', () => {
  it('shows Saved for SAVED_FLASH_MS after a successful save, and the form is clean again', async () => {
    chat.profileName = 'Atlas Prime '
    expect(guard.profileDirty()).toBe(true)
    expect(await profile.saveProfile()).toBe(true)
    expect(server.patches[0].name).toBe('Atlas Prime')
    expect(chat.agents[0].name).toBe('Atlas Prime')
    expect(guard.profileDirty()).toBe(false)
    expect(chat.profileSaved.details).toBe(true)
    await vi.advanceTimersByTimeAsync(SAVED_FLASH_MS)
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
    await vi.advanceTimersByTimeAsync(SAVED_FLASH_MS)
    expect(chat.profileSaved.label).toBe(false)
  })

  it('ticks an instant setting (avatar) after it saves', async () => {
    await profile.patchProfileSetting(profile.SAVED_TICK.avatar, { avatarColor: '#3B82F6' })
    expect(chat.profileSaved.avatar).toBe(true)
  })
})

describe('unsaved changes guard', () => {
  it('leaves at once when there is nothing unsaved', () => {
    const leave = vi.fn()
    guard.guardUnsaved(leave)
    expect(leave).toHaveBeenCalledOnce()
    expect(chat.unsavedPrompt).toBe(false)
  })

  it('holds the leave and asks while Details has edits', () => {
    const leave = vi.fn()
    chat.profileSummary = 'Plans trips and hotels'
    guard.guardUnsaved(leave)
    expect(leave).not.toHaveBeenCalled()
    expect(chat.unsavedPrompt).toBe(true)
  })

  it('Discard restores the saved profile, then leaves', () => {
    const leave = vi.fn()
    chat.profileInstructions = 'Be thorough.'
    guard.guardUnsaved(leave)
    profile.discardAndLeave()
    expect(chat.profileInstructions).toBe('Be brief.')
    expect(leave).toHaveBeenCalledOnce()
    expect(chat.unsavedPrompt).toBe(false)
    expect(server.patches).toEqual([])
  })

  it('Save saves first, then leaves', async () => {
    const leave = vi.fn()
    chat.profileName = 'Atlas Prime'
    guard.guardUnsaved(leave)
    await profile.saveAndLeave()
    expect(server.patches).toHaveLength(1)
    expect(leave).toHaveBeenCalledOnce()
    expect(chat.unsavedPrompt).toBe(false)
  })

  it('Save that fails stays, with the prompt still up', async () => {
    const leave = vi.fn()
    server.fail = true
    chat.profileName = 'Atlas Prime'
    guard.guardUnsaved(leave)
    await profile.saveAndLeave()
    expect(leave).not.toHaveBeenCalled()
    expect(chat.unsavedPrompt).toBe(true)
    expect(chat.profileError).toBe('Could not save.')
  })

  it('does not ask while the panel is closed', () => {
    const leave = vi.fn()
    chat.sidePanelOpen = false
    chat.profileName = 'Atlas Prime'
    guard.guardUnsaved(leave)
    expect(leave).toHaveBeenCalledOnce()
  })
})
