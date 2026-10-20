import { describe, expect, it } from 'bun:test'
import { agent, approval as makeApproval, message, routine as makeRoutine, run as makeRun, skill as makeSkill } from '../testFixtures.ts'
import type { Skill } from '../types.ts'
import { SKILL_LIMIT, approvalAwaitsDecision, pendingApprovals, isAwaitingComputer, openWelcomeChoices, routineCreatedSince, skillMatches } from './selectors.ts'

const skill = (name: string, extra: Partial<Skill> = {}): Skill => makeSkill({ id: name, name, ...extra })

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
  const run = makeRun({ id: 'run1' })
  const approval = (state: string, runId = 'run1') => makeApproval({ id: 'a1', runId, state })

  it('accepts a pending approval from this run', () => {
    expect(approvalAwaitsDecision(approval('pending'), run)).toBe(true)
  })

  it('rejects decided approvals, other runs and no run', () => {
    expect(approvalAwaitsDecision(approval('approved'), run)).toBe(false)
    expect(approvalAwaitsDecision(approval('pending', 'run2'), run)).toBe(false)
    expect(approvalAwaitsDecision(approval('pending'), undefined)).toBe(false)
  })
})

describe('routine created during a reply', () => {
  const routine = (id: string, agentId: string, createdAt: string) => makeRoutine({ id, agentId, createdAt })
  const since = '2026-10-01T08:00:00Z'

  it('picks the newest routine this bot created since the message', () => {
    const routines = [routine('old', 'a', '2026-10-01T07:59:59Z'), routine('r1', 'a', '2026-10-01T08:00:02Z'), routine('r2', 'a', '2026-10-01T08:00:05Z')]
    expect(routineCreatedSince(routines, 'a', since)?.id).toBe('r2')
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
  const choices = [{ id: 'a', label: 'A', subtitle: 'First', message: 'Do A' }]
  const welcome = message({ id: 'w', role: 'assistant', text: 'Hi Ada', choices })

  it('offers the ideas while the welcome is the latest message', () => {
    expect(openWelcomeChoices([welcome])).toEqual({ id: 'w', options: choices })
  })

  it('closes once the owner has written (a pick or their own words)', () => {
    expect(openWelcomeChoices([welcome, message({ id: 'u', role: 'user', text: 'Do A' })])).toBeNull()
  })

  it('ignores messages without ideas', () => {
    expect(openWelcomeChoices([message({ id: 'r', role: 'assistant', text: 'Done' })])).toBeNull()
    expect(openWelcomeChoices([])).toBeNull()
  })
})

describe('waiting for the computer', () => {
  it('holds while a sent message waits for the bot to be ready', () => {
    expect(isAwaitingComputer(agent({ status: 'provisioning', queuedMessage: true }))).toBe(true)
    expect(isAwaitingComputer(agent({ status: 'idle', queuedMessage: true }))).toBe(true)
  })

  it('shows as soon as the owner sends to a bot still being set up', () => {
    expect(isAwaitingComputer(agent({ id: 'b', status: 'provisioning' }), 'b')).toBe(true)
  })

  it('stays hidden when nothing is waiting', () => {
    expect(isAwaitingComputer(agent({ status: 'provisioning' }))).toBe(false)
    expect(isAwaitingComputer(agent({ id: 'b', status: 'idle' }), 'b')).toBe(false)
    expect(isAwaitingComputer(agent({ id: 'b', status: 'provisioning' }), 'other')).toBe(false)
    expect(isAwaitingComputer(null, 'b')).toBe(false)
  })
})

describe('pendingApprovals', () => {
  it('keeps only approvals still waiting on the owner', () => {
    const approvals = [makeApproval({ id: 'a', state: 'pending' }), makeApproval({ id: 'b', state: 'approved' }), makeApproval({ id: 'c', state: 'denied' })]
    expect(pendingApprovals(approvals).map(item => item.id)).toEqual(['a'])
    expect(pendingApprovals(undefined)).toEqual([])
  })
})
