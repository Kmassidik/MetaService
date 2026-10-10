import { describe, expect, it } from 'vitest'
import { SKILL_LIMIT, approvalAwaitsDecision, pendingApprovals, isAwaitingComputer, openWelcomeChoices, routineCreatedSince, skillMatches } from './selectors.js'

const skill = (name, extra = {}) => ({ id: name, name, enabled: true, state: 'active', ...extra })

// Regression: the / picker once showed every loaded skill, ignoring the query and the filters.
describe('skill picker candidates', () => {
  it('returns nothing when the query matches no skill', () => {
    expect(skillMatches([skill('Summarise'), skill('Translate')], 'zzz')).toEqual([])
  })

  it('filters by the typed query', () => {
    const names = skillMatches([skill('Summarise'), skill('Translate')], 'trans').map(s => s.name)
    expect(names).toEqual(['Translate'])
  })

  it('leaves out disabled and inactive skills', () => {
    const skills = [skill('On'), skill('Off', { enabled: false }), skill('Draft', { state: 'draft' })]
    expect(skillMatches(skills, '').map(s => s.name)).toEqual(['On'])
  })

  it('caps the list', () => {
    const many = Array.from({ length: SKILL_LIMIT + 3 }, (_, i) => skill(`Skill ${i}`))
    expect(skillMatches(many, '')).toHaveLength(SKILL_LIMIT)
  })
})

// Regression: decideRunApproval compared against 'chat.pending', so Approve and Deny never fired.
describe('approval decisions', () => {
  const run = { id: 'run1' }
  const approval = (state, runId = 'run1') => ({ id: 'a1', runId, state })

  it('accepts a pending approval from this run', () => {
    expect(approvalAwaitsDecision(approval('pending'), run)).toBe(true)
  })

  it('rejects decided approvals, other runs and no run', () => {
    expect(approvalAwaitsDecision(approval('approved'), run)).toBe(false)
    expect(approvalAwaitsDecision(approval('pending', 'run2'), run)).toBe(false)
    expect(approvalAwaitsDecision(approval('pending'), null)).toBe(false)
  })
})

describe('routine created during a reply', () => {
  const routine = (id, agentId, createdAt) => ({ id, agentId, createdAt })
  const since = '2026-10-01T08:00:00Z'

  it('picks the newest routine this bot created since the message', () => {
    const routines = [routine('old', 'a', '2026-10-01T07:59:59Z'), routine('r1', 'a', '2026-10-01T08:00:02Z'), routine('r2', 'a', '2026-10-01T08:00:05Z')]
    expect(routineCreatedSince(routines, 'a', since).id).toBe('r2')
  })

  it('ignores other bots and older routines', () => {
    const routines = [routine('other', 'b', '2026-10-01T08:00:05Z'), routine('old', 'a', '2026-10-01T07:00:00Z')]
    expect(routineCreatedSince(routines, 'a', since)).toBeNull()
  })

  it('returns null without a usable time or bot', () => {
    expect(routineCreatedSince([routine('r', 'a', since)], 'a', 'not a date')).toBeNull()
    expect(routineCreatedSince([routine('r', 'a', since)], '', since)).toBeNull()
  })
})

describe('New bot welcome choices', () => {
  const welcome = { id: 'w', role: 'assistant', text: 'Hi Ada', choices: [{ id: 'a', label: 'A', message: 'Do A' }] }

  it('offers the ideas while the welcome is the latest message', () => {
    expect(openWelcomeChoices([welcome])).toEqual({ id: 'w', options: welcome.choices })
  })

  it('closes once the owner has written (a pick or their own words)', () => {
    expect(openWelcomeChoices([welcome, { id: 'u', role: 'user', text: 'Do A' }])).toBeNull()
  })

  it('ignores messages without ideas', () => {
    expect(openWelcomeChoices([{ id: 'r', role: 'assistant', text: 'Done' }])).toBeNull()
    expect(openWelcomeChoices([])).toBeNull()
  })
})

describe('waiting for the computer', () => {
  it('holds while a sent message waits for the bot to be ready', () => {
    expect(isAwaitingComputer({ status: 'provisioning', queuedMessage: true })).toBe(true)
    expect(isAwaitingComputer({ status: 'idle', queuedMessage: true })).toBe(true)
  })

  it('shows as soon as the owner sends to a bot still being set up', () => {
    expect(isAwaitingComputer({ id: 'b', status: 'provisioning' }, 'b')).toBe(true)
  })

  it('stays hidden when nothing is waiting', () => {
    expect(isAwaitingComputer({ status: 'provisioning' })).toBe(false)
    expect(isAwaitingComputer({ id: 'b', status: 'idle' }, 'b')).toBe(false)
    expect(isAwaitingComputer({ id: 'b', status: 'provisioning' }, 'other')).toBe(false)
    expect(isAwaitingComputer(null, 'b')).toBe(false)
  })
})

describe('pendingApprovals', () => {
  it('keeps only approvals still waiting on the owner', () => {
    const approvals = [{ id: 'a', state: 'pending' }, { id: 'b', state: 'approved' }, { id: 'c', state: 'denied' }]
    expect(pendingApprovals(approvals).map(item => item.id)).toEqual(['a'])
    expect(pendingApprovals(undefined)).toEqual([])
  })
})
