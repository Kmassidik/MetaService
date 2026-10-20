// activeAsk: answered asks are skipped, and the latest unanswered ask wins.
import { beforeEach, describe, expect, it } from 'bun:test'
import { run, runEvent, session } from '../testFixtures.ts'

const { chat } = await import('./state.svelte.ts')
const { activeAsk } = await import('./runs.svelte.ts')

const options = [{ id: 'a', label: 'A' }, { id: 'b', label: 'B' }]
const ask = (askId: string, sequence: number) => runEvent({ kind: 'ask', sequence, payload: { askId, options } })
const answered = (askId: string, sequence: number) => runEvent({ kind: 'ask_answered', sequence, payload: { askId } })

function showEvents(events: ReturnType<typeof runEvent>[]): void {
  chat.runEvents = { r1: events }
}

beforeEach(() => {
  Object.assign(chat, {
    session: session(), selectedId: 'a1', agentRuns: { a1: [run()] }, runEvents: {}, answeredAsks: {},
  })
})

describe('activeAsk', () => {
  it('is null with no events', () => {
    expect(activeAsk()).toBeNull()
  })

  it('is null with no chat selected', () => {
    showEvents([ask('q1', 1)])
    chat.selectedId = ''
    expect(activeAsk()).toBeNull()
  })

  it('is the latest unanswered ask', () => {
    showEvents([ask('q1', 1), ask('q2', 2)])
    expect(activeAsk()?.askId).toBe('q2')
  })

  it('skips an ask the server says was answered', () => {
    showEvents([ask('q1', 1), ask('q2', 2), answered('q2', 3)])
    expect(activeAsk()?.askId).toBe('q1')
  })

  it('skips an ask answered on this screen', () => {
    showEvents([ask('q1', 1), ask('q2', 2)])
    chat.answeredAsks = { q2: ['yes'] }
    expect(activeAsk()?.askId).toBe('q1')
  })

  it('is null when every ask is answered', () => {
    showEvents([ask('q1', 1), answered('q1', 2)])
    expect(activeAsk()).toBeNull()
  })
})
