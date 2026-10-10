import { describe, expect, it } from 'vitest'
import { SAVE_STATE, canSave, isProfileDirty, saveLabel, saveState, savedProfile } from './profileForm.js'

const agent = { id: 'b1', name: 'Atlas', title: 'Travel planner', summary: 'Plans trips', description: 'Be brief.' }
const formOf = bot => ({ name: bot.name, summary: bot.summary, instructions: bot.description })

describe('dirty tracking', () => {
  it('is clean when the form holds what the bot saved', () => {
    expect(isProfileDirty(formOf(agent), agent)).toBe(false)
  })

  it('ignores whitespace at either end, like Save does', () => {
    expect(isProfileDirty({ name: '  Atlas ', summary: 'Plans trips\n', instructions: ' Be brief.' }, agent)).toBe(false)
  })

  it('is dirty when any edited field changes', () => {
    expect(isProfileDirty({ ...formOf(agent), name: 'Atlas 2' }, agent)).toBe(true)
    expect(isProfileDirty({ ...formOf(agent), summary: '' }, agent)).toBe(true)
    expect(isProfileDirty({ ...formOf(agent), instructions: 'Be thorough.' }, agent)).toBe(true)
  })

  it('compares instructions with the bot description, and missing fields as empty', () => {
    const bare = { id: 'b2', name: 'New bot' }
    expect(savedProfile(bare)).toEqual({ name: 'New bot', summary: '', instructions: '' })
    expect(isProfileDirty({ name: 'New bot', summary: '', instructions: '' }, bare)).toBe(false)
    expect(isProfileDirty({ name: 'New bot', summary: undefined, instructions: null }, bare)).toBe(false)
  })

  it('is never dirty without a bot', () => {
    expect(isProfileDirty({ name: 'x' }, null)).toBe(false)
  })

  it('ignores the label (title): it saves on its own', () => {
    expect(isProfileDirty({ ...formOf(agent), title: 'Other' }, agent)).toBe(false)
  })
})

describe('save button', () => {
  it('saving wins, then unsaved edits, then the brief saved state', () => {
    expect(saveState({ saving: true, dirty: true, justSaved: true })).toBe(SAVE_STATE.saving)
    expect(saveState({ dirty: true, justSaved: true })).toBe(SAVE_STATE.dirty)
    expect(saveState({ justSaved: true })).toBe(SAVE_STATE.saved)
    expect(saveState({})).toBe(SAVE_STATE.clean)
  })

  it('says what will happen', () => {
    expect(saveLabel(SAVE_STATE.clean)).toBe('Save')
    expect(saveLabel(SAVE_STATE.dirty)).toBe('Save changes')
    expect(saveLabel(SAVE_STATE.saving)).toBe('Saving…')
    expect(saveLabel(SAVE_STATE.saved)).toBe('Saved ✓')
  })

  it('is enabled only with edits and nothing locking the form', () => {
    expect(canSave(SAVE_STATE.dirty, false)).toBe(true)
    expect(canSave(SAVE_STATE.dirty, true)).toBe(false)
    expect(canSave(SAVE_STATE.clean, false)).toBe(false)
    expect(canSave(SAVE_STATE.saved, false)).toBe(false)
    expect(canSave(SAVE_STATE.saving, false)).toBe(false)
  })
})
