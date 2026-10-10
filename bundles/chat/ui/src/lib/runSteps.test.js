import { describe, expect, it } from 'vitest'
import { runSteps, stepLabel, stepText, stepsByReply } from './runSteps.js'

let sequence = 0
const runtime = payload => ({ sequence: ++sequence, kind: 'runtime', payload })
const tool = (name, phase = 'start', extra = {}) => runtime({ type: 'tool', name, phase, ...extra })
const event = (kind, payload = {}) => ({ sequence: ++sequence, kind, payload })
const texts = events => runSteps(events).map(stepText)

describe('stepLabel', () => {
  it('names a tool call in plain words when it starts', () => {
    expect(stepLabel(tool('browser'))).toBe('Browsed the web')
    expect(stepLabel(tool('exec'))).toBe('Ran a command')
    expect(stepLabel(tool('some_new_tool'))).toBe('Used a tool')
  })

  it('hides the end of a tool call and internal plumbing', () => {
    expect(stepLabel(tool('browser', 'end'))).toBe('')
    expect(stepLabel(tool('browser', 'result'))).toBe('')
    expect(stepLabel(runtime({ type: 'lifecycle', phase: 'start' }))).toBe('')
    expect(stepLabel(runtime({ type: 'lifecycle', phase: 'end' }))).toBe('')
    expect(stepLabel(runtime({ type: 'routing', model: 'm', classifierModel: 'c' }))).toBe('')
    expect(stepLabel(runtime({ type: 'compaction' }))).toBe('')
    expect(stepLabel(runtime({ type: 'run', status: 'running' }))).toBe('')
    expect(stepLabel(runtime({ type: 'broker', name: 'maas_research', phase: 'queued' }))).toBe('')
    expect(stepLabel(runtime({ type: 'steer', phase: 'accepted' }))).toBe('')
  })

  it('hides chat-level and state events that are not steps', () => {
    for (const kind of ['state', 'step', 'ask', 'ask_answered', 'card', 'card_resolved', 'profile', 'message.queued', 'message.taken']) {
      expect(stepLabel(event(kind, { state: 'running', title: 'x' }))).toBe('')
    }
    expect(stepLabel(null)).toBe('')
    expect(stepLabel({})).toBe('')
  })

  it('says who did it when a group member or helper worked', () => {
    const childId = '0f8fad5b-d9cb-469f-a165-70867728950e'
    expect(stepLabel(tool('browser', 'start', { childId, memberName: 'Atlas' }))).toBe('Atlas browsed the web')
    expect(stepLabel(tool('read', 'start', { childId }))).toBe('A helper read a file')
    expect(stepLabel(runtime({ type: 'child', phase: 'running', childId, memberName: 'Atlas' }))).toBe('Atlas started on part of the task')
    expect(stepLabel(runtime({ type: 'child', phase: 'completed', childId }))).toBe('A helper finished its part')
    expect(stepLabel(runtime({ type: 'child', phase: 'queued', childId }))).toBe('')
  })

  it('shows approvals and problems', () => {
    expect(stepLabel(event('approval.requested'))).toBe('Asked for your approval')
    expect(stepLabel(event('approval.consumed'))).toBe('Did the approved action')
    expect(stepLabel(runtime({ type: 'error' }))).toBe('Ran into a problem')
  })
})

describe('runSteps', () => {
  it('lists only meaningful steps, in order', () => {
    const events = [
      event('state', { state: 'running' }),
      runtime({ type: 'lifecycle', phase: 'start' }),
      tool('browser'), tool('browser', 'end'),
      tool('read'), tool('read', 'end'),
      runtime({ type: 'lifecycle', phase: 'end' }),
    ]
    expect(texts(events)).toEqual(['Browsed the web', 'Read a file'])
  })

  it('folds repeats in a row into one step with a count', () => {
    const events = [tool('browser'), tool('browser', 'end'), tool('browser'), tool('browser'), tool('exec'), tool('browser')]
    expect(texts(events)).toEqual(['Browsed the web · 3 times', 'Ran a command', 'Browsed the web'])
  })

  it('is empty when nothing meaningful happened', () => {
    expect(runSteps([runtime({ type: 'lifecycle', phase: 'start' }), event('state')])).toEqual([])
    expect(runSteps(undefined)).toEqual([])
  })

  it('never exposes anything beyond the label', () => {
    const [step] = runSteps([tool('browser', 'start', { arguments: { url: 'https://secret.example' } })])
    expect(Object.keys(step).sort()).toEqual(['count', 'id', 'text'])
    expect(JSON.stringify(step)).not.toContain('secret')
  })
})

describe('stepsByReply', () => {
  const message = (id, role, createdAt) => ({ id, role, createdAt, text: id })
  const run = (id, state, createdAt) => ({ id, state, createdAt })
  const messages = [
    message('u1', 'user', '2026-10-01T10:00:00Z'),
    message('b1', 'assistant', '2026-10-01T10:00:30Z'),
    message('u2', 'user', '2026-10-01T10:05:00Z'),
    message('b2', 'assistant', '2026-10-01T10:05:40Z'),
    message('b2b', 'assistant', '2026-10-01T10:05:50Z'),
  ]

  it('puts each finished run’s steps under its own reply', () => {
    const runs = [run('r2', 'succeeded', '2026-10-01T10:05:00Z'), run('r1', 'succeeded', '2026-10-01T10:00:00Z')]
    const events = { r1: [tool('browser')], r2: [tool('exec')] }
    const byReply = stepsByReply(messages, runs, events)
    expect(Object.keys(byReply).sort()).toEqual(['b1', 'b2'])
    expect(byReply.b1.map(stepText)).toEqual(['Browsed the web'])
    expect(byReply.b2.map(stepText)).toEqual(['Ran a command'])
  })

  it('skips running runs, runs without steps and runs whose events are not loaded', () => {
    const runs = [run('r1', 'succeeded', '2026-10-01T10:00:00Z'), run('r2', 'running', '2026-10-01T10:05:00Z')]
    expect(stepsByReply(messages, runs, { r2: [tool('exec')] })).toEqual({})
    expect(stepsByReply(messages, runs, { r1: [runtime({ type: 'lifecycle', phase: 'start' })] })).toEqual({})
  })

  it('does not pin an older run’s steps on a reply that came after the next run started', () => {
    const runs = [run('r1', 'failed', '2026-10-01T10:00:20Z'), run('r2', 'succeeded', '2026-10-01T10:00:25Z')]
    const byReply = stepsByReply(messages, runs, { r1: [tool('browser')] })
    expect(byReply).toEqual({})
  })
})
