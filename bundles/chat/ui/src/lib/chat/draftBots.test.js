import { describe, expect, it } from 'vitest'
import { draftBot, isDraftBot, keepDraftBots, replaceDraftBot, watchesRuns } from './draftBots.js'

const avatar = { avatarShape: 'blob', avatarColor: '#2563eb' }

describe('draft bots', () => {
  it('stand in as a provisioning New bot with the chosen avatar', () => {
    const draft = draftBot(avatar, new Date('2026-10-01T00:00:00Z'))
    expect(isDraftBot(draft.id)).toBe(true)
    expect(draft).toMatchObject({ name: 'New bot', kind: 'bot', status: 'provisioning', ...avatar, createdAt: '2026-10-01T00:00:00.000Z' })
  })

  it('never mistake a server id for a draft', () => {
    expect(isDraftBot('3f1c2a4e-0000-4000-8000-000000000000')).toBe(false)
    expect(isDraftBot(undefined)).toBe(false)
  })

  it('survive a roster refresh that does not know them yet', () => {
    const draft = draftBot(avatar)
    const server = [{ id: 'a' }, { id: 'b' }]
    expect(keepDraftBots([{ id: 'old' }, draft], server)).toEqual([draft, ...server])
  })

  it('are replaced by the real bot, which also replaces a stale copy of a reopened bot', () => {
    const draft = draftBot(avatar)
    const reopened = { id: 'b', name: 'New bot' }
    expect(replaceDraftBot([draft, { id: 'a' }, { id: 'b' }], draft.id, reopened)).toEqual([reopened, { id: 'a' }])
  })
})

describe('task status for a new bot', () => {
  it('never asks the server about a draft, which has no runs yet (the red flash on New bot)', () => {
    expect(watchesRuns('draft-1790842012863', 'csrf')).toBe(false)
  })

  it('watches a saved bot only while signed in', () => {
    expect(watchesRuns('77be7d2d-b6fc-4633-9ecf-518e4f9c4dc3', 'csrf')).toBe(true)
    expect(watchesRuns('77be7d2d-b6fc-4633-9ecf-518e4f9c4dc3', '')).toBe(false)
    expect(watchesRuns('', 'csrf')).toBe(false)
  })
})
