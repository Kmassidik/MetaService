import { describe, expect, it } from 'vitest'
import {
  FOLLOW_UP_STATE, SEND_MODE, followUpRequest, followUpState, hasSendableInput, sendMode, waitingFollowUps,
} from './sendMode.js'

describe('sendMode', () => {
  it('starts a turn when no task is running', () => {
    expect(sendMode({ runActive: false, botBusy: false })).toBe(SEND_MODE.turn)
  })

  it('queues a follow-up while a task runs', () => {
    expect(sendMode({ runActive: true, runState: 'running', botBusy: true })).toBe(SEND_MODE.followUp)
    expect(sendMode({ runActive: true, runState: 'queued', botBusy: true })).toBe(SEND_MODE.followUp)
    expect(sendMode({ runActive: true, runState: 'awaiting_approval', botBusy: true })).toBe(SEND_MODE.followUp)
  })

  it('is closed while the task is stopping or before the busy bot’s task is known', () => {
    expect(sendMode({ runActive: true, runState: 'cancelling', botBusy: true })).toBe(SEND_MODE.closed)
    expect(sendMode({ runActive: false, botBusy: true })).toBe(SEND_MODE.closed)
  })
})

describe('hasSendableInput', () => {
  it('a turn takes text or files', () => {
    expect(hasSendableInput(SEND_MODE.turn, { text: 'hi' })).toBe(true)
    expect(hasSendableInput(SEND_MODE.turn, { attachmentCount: 1 })).toBe(true)
    expect(hasSendableInput(SEND_MODE.turn, {})).toBe(false)
  })

  it('a follow-up takes text only', () => {
    expect(hasSendableInput(SEND_MODE.followUp, { text: 'also check JAL' })).toBe(true)
    expect(hasSendableInput(SEND_MODE.followUp, { text: 'with a file', attachmentCount: 1 })).toBe(false)
    expect(hasSendableInput(SEND_MODE.followUp, { attachmentCount: 1 })).toBe(false)
  })

  it('nothing sends while closed', () => {
    expect(hasSendableInput(SEND_MODE.closed, { text: 'hi' })).toBe(false)
  })
})

describe('followUpRequest', () => {
  it('posts the text to the running task as a queued message', () => {
    expect(followUpRequest('run 1', 'also check JAL')).toEqual({
      path: '/api/runs/run%201/messages', body: { text: 'also check JAL', kind: 'queued' },
    })
  })
})

describe('follow-up state', () => {
  const run = (state, createdAt = '2026-10-01T10:00:00Z') => ({ id: 'r1', state, createdAt })
  const item = (extra = {}) => ({ id: 'm1', runId: 'r1', text: 'also check JAL', confirmed: true, ...extra })
  const said = (text, createdAt) => ({ id: createdAt, role: 'user', text, createdAt })

  it('is sending until the server confirms it', () => {
    expect(followUpState(item({ confirmed: false }), [], [run('running')])).toBe(FOLLOW_UP_STATE.sending)
  })

  it('stays queued while the task works, and after it finishes until its turn starts', () => {
    expect(followUpState(item(), [], [run('running')])).toBe(FOLLOW_UP_STATE.queued)
    expect(followUpState(item(), [], [run('succeeded')])).toBe(FOLLOW_UP_STATE.queued)
  })

  it('is delivered once the chat shows it as the owner’s message after the task started', () => {
    const history = [said('also check JAL', '2026-10-01T10:02:00Z')]
    expect(followUpState(item(), history, [run('succeeded')])).toBe(FOLLOW_UP_STATE.delivered)
    const earlier = [said('also check JAL', '2026-10-01T09:59:00Z')]
    expect(followUpState(item(), earlier, [run('succeeded')])).toBe(FOLLOW_UP_STATE.queued)
  })

  it('is dropped when the task was stopped', () => {
    expect(followUpState(item(), [], [run('cancelled')])).toBe(FOLLOW_UP_STATE.dropped)
  })

  it('waitingFollowUps hides delivered ones and labels the rest', () => {
    const items = [item(), item({ id: 'm2', text: 'and ANA' })]
    const history = [said('also check JAL', '2026-10-01T10:02:00Z')]
    expect(waitingFollowUps(items, history, [run('succeeded')]).map(i => [i.id, i.state])).toEqual([['m2', 'queued']])
  })
})
