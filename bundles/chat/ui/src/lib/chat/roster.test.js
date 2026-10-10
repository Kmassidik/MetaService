import { describe, expect, it } from 'vitest'
import { activityTime, buildRoster, groupFaces, hiddenRoster, isBusy, matchesQuery, rowPreview, unreadLabel } from './roster.js'

const NOW = Date.parse('2026-10-01T12:00:00Z')
const agent = (id, extra = {}) => ({ id, name: id, kind: 'bot', status: 'idle', createdAt: '2026-09-01T00:00:00Z', ...extra })

describe('roster ordering', () => {
  it('merges bots and group chats, newest activity first', () => {
    const agents = [
      agent('old'),
      agent('team', { kind: 'team', createdAt: '2026-09-20T00:00:00Z' }),
      agent('new', { createdAt: '2026-09-10T00:00:00Z' }),
    ]
    expect(buildRoster(agents, { now: NOW }).map(a => a.id)).toEqual(['team', 'new', 'old'])
  })

  it('keeps pinned bots on top regardless of activity', () => {
    const agents = [agent('recent', { createdAt: '2026-09-30T00:00:00Z' }), agent('pinned', { pinned: true })]
    expect(buildRoster(agents, { now: NOW }).map(a => a.id)).toEqual(['pinned', 'recent'])
  })

  it('uses caller-provided message times over creation time', () => {
    const agents = [agent('a', { createdAt: '2026-09-30T00:00:00Z' }), agent('b')]
    const activityAt = { b: '2026-10-01T11:00:00Z' }
    expect(buildRoster(agents, { activityAt, now: NOW }).map(a => a.id)).toEqual(['b', 'a'])
  })

  it('treats a working bot as the most recent', () => {
    expect(activityTime(agent('x', { status: 'running' }), {}, NOW)).toBe(NOW)
  })

  it('excludes hidden bots and applies the search query', () => {
    const agents = [agent('Atlas', { title: 'Travel' }), agent('Pixel', { hidden: true }), agent('Lincoln')]
    expect(buildRoster(agents, { query: 'travel', now: NOW }).map(a => a.id)).toEqual(['Atlas'])
    expect(hiddenRoster(agents).map(a => a.id)).toEqual(['Pixel'])
  })
})

describe('roster rows', () => {
  it('matches on name, title, summary and description', () => {
    expect(matchesQuery(agent('x', { summary: 'Inbox triage' }), 'inbox')).toBe(true)
    expect(matchesQuery(agent('x'), '  ')).toBe(true)
  })

  it('stacks the lead and one member for a group', () => {
    const bots = [agent('a'), agent('b'), agent('c')]
    const team = agent('t', { kind: 'team', leadAgentId: 'a', memberAgentIds: ['a', 'b', 'c'] })
    expect(groupFaces(team, bots).map(a => a.id)).toEqual(['a', 'b'])
  })

  it('previews status, then pending text, then the last message', () => {
    expect(rowPreview(agent('x', { status: 'failed' }))).toBe('Setup needs attention')
    expect(rowPreview(agent('x', { status: 'provisioning', lastMessagePreview: 'Hi Ada 👋' }))).toBe('Hi Ada 👋')
    expect(rowPreview(agent('x', { lastMessagePreview: 'hi' }), { id: 'x', text: 'typing' })).toBe('typing')
    expect(rowPreview(agent('x', { lastMessagePreview: 'hi' }))).toBe('hi')
  })

  it('strips markdown markers from the preview', () => {
    expect(rowPreview(agent('x', { lastMessagePreview: 'The best is **ANA**\n- `JAL`' }))).toBe('The best is ANA - JAL')
  })

  it('caps unread counts and hides them for the open chat', () => {
    expect(unreadLabel(agent('x', { unreadCount: 12 }))).toBe('9+')
    expect(unreadLabel(agent('x', { unreadCount: 2 }), 'x')).toBe('')
    expect(unreadLabel(agent('x'))).toBe('')
  })
})

describe('sidebar spinner', () => {
  it('spins while a bot replies or holds a message for its computer', () => {
    expect(isBusy(agent('x', { status: 'running' }))).toBe(true)
    expect(isBusy(agent('x', { status: 'provisioning', queuedMessage: true }))).toBe(true)
    expect(isBusy(agent('x'), { id: 'x' })).toBe(true)
  })

  it('stays calm for a new bot whose computer is still starting', () => {
    expect(isBusy(agent('x', { status: 'provisioning' }))).toBe(false)
    expect(isBusy(agent('x'))).toBe(false)
  })
})
