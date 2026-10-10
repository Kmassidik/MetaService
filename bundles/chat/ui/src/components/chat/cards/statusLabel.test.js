import { describe, expect, it } from 'vitest'
import { STATUS_TONE, statusLabel } from './statusLabel.js'

const base = { name: 'Atlas', run: null, runActive: false, sending: false, waitingForAnswer: false, approvalPending: false, computerLive: false }

describe('statusLabel', () => {
  it('is empty when nothing is happening', () => {
    expect(statusLabel(base)).toBeNull()
  })

  it('says the bot is working while a run is active', () => {
    expect(statusLabel({ ...base, runActive: true })).toEqual({ text: 'Atlas is working…', tone: STATUS_TONE.working })
  })

  it('mentions the computer while it is live', () => {
    expect(statusLabel({ ...base, runActive: true, computerLive: true }).text).toBe('Atlas is using the computer…')
  })

  it('prefers waiting for an answer over working', () => {
    expect(statusLabel({ ...base, runActive: true, waitingForAnswer: true }).text).toBe('Waiting for your answer')
  })

  // Regression: a sign-in, connect, secret or suggest card showed "Atlas is working…".
  it('waits for you while a card needs your input', () => {
    expect(statusLabel({ ...base, runActive: true, waitingForInput: true })).toEqual({ text: 'Waiting for you', tone: STATUS_TONE.waiting })
  })

  it('reports approvals and stopping', () => {
    expect(statusLabel({ ...base, run: { state: 'awaiting_approval' } }).text).toBe('Waiting for your approval')
    expect(statusLabel({ ...base, run: { state: 'cancelling' }, runActive: true }).text).toBe('Stopping…')
  })

  it('reports a failed reply', () => {
    expect(statusLabel({ ...base, run: { state: 'failed', error: 'x' } }).tone).toBe(STATUS_TONE.problem)
  })
})
