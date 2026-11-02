import { expect, test } from 'bun:test'
import { LOST_CONTACT_TEXT, STEP_MAX_CHARS, STOPPED_SHOWN_MS, TIMED_OUT_TEXT, WAITING_STEP, isOpenState, isRetryType, isStoppedState, jobLine, stateWords, stepOf, stoppedText } from './jobState.ts'
import { reasonText } from './pendingVms.ts'
import { command } from './testing.ts'

const T0 = Date.parse('2026-11-03T10:00:00Z')
const order = (extra: Parameters<typeof command>[0] = {}) => command({ id: 'c1', type: 'delete', machine: 'm', workload_id: 'w1', state: 'running', created_at: '2026-11-03T09:59:00Z', ...extra })

test('open and final states are told apart, the four final ones included', () => {
  expect(['queued', 'running'].every(isOpenState)).toBe(true)
  expect(['succeeded', 'failed', 'timed_out', 'lost_contact'].some(isOpenState)).toBe(false)
  expect(['failed', 'timed_out', 'lost_contact'].every(isStoppedState)).toBe(true)
  expect(isStoppedState('succeeded')).toBe(false)
  expect(isOpenState('something_new')).toBe(false)
})

test('a step of the wrong type is unknown, never made into text', () => {
  for (const wrong of [0, false, 12, {}, [], undefined, null]) expect(stepOf({ step: wrong as never })).toBeNull()
  expect(stepOf({ step: '' })).toBeNull()
  expect(stepOf({ step: 'Deleting' })).toBe('Deleting')
})

test('a step loses control characters and colour codes and is cut', () => {
  expect(stepOf({ step: 'Del\u0000et\u0007ing\u001b[31m now\u001b[0m\n\tok' })).toBe('Deleting now ok')
  const long = stepOf({ step: 'x'.repeat(5000) })
  expect(Array.from(long ?? '').length).toBe(STEP_MAX_CHARS)
  expect(stepOf({ step: '<img src=x onerror=alert(1)>' })).toBe('<img src=x onerror=alert(1)>')
})

test('a running delete shows its step; with none it says it waits', () => {
  expect(jobLine([order({ step: 'Backing up (this can take several minutes for big disks)' })], 'm', 'w1', T0)).toEqual({ kind: 'working', type: 'delete', text: 'Backing up (this can take several minutes for big disks)', retry: null })
  expect(jobLine([order({ state: 'queued' })], 'm', 'w1', T0)?.text).toBe(WAITING_STEP)
  expect(jobLine([order({ step: 7 as never })], 'm', 'w1', T0)?.text).toBe(WAITING_STEP)
})

test('timed out says it took too long, nothing more was done, check the machine', () => {
  const line = jobLine([order({ state: 'timed_out', finished_at: '2026-11-03T09:59:30Z' })], 'm', 'w1', T0)
  expect(line?.text).toBe(TIMED_OUT_TEXT)
  expect(TIMED_OUT_TEXT).toContain('took too long')
  expect(TIMED_OUT_TEXT).toContain('Check the machine')
  expect(line?.retry).toBe('delete')
})

test('lost contact names the last step when the parent gave no reason', () => {
  expect(stoppedText(order({ state: 'lost_contact', step: 'Deleting' }))).toBe(`${LOST_CONTACT_TEXT} The last step was Deleting.`)
  expect(stoppedText(order({ state: 'lost_contact' }))).toBe(LOST_CONTACT_TEXT)
})

test("the parent's own plain reason wins over the fixed words", () => {
  expect(stoppedText(order({ state: 'timed_out', result: { error: 'It ran 30 minutes.' } }))).toBe('It ran 30 minutes.')
  expect(stoppedText(order({ state: 'failed', result: { error: 5 as never } }))).toBe('The VM could not be deleted.')
})

test('Retry only for Delete, Start and Stop; never Create; never for a success', () => {
  expect(['delete', 'start', 'stop'].every(isRetryType)).toBe(true)
  expect(isRetryType('create')).toBe(false)
  for (const type of ['delete', 'start', 'stop']) for (const state of ['failed', 'timed_out', 'lost_contact']) expect(jobLine([order({ type, state })], 'm', 'w1', T0)?.retry).toBe(type as never)
  expect(jobLine([order({ type: 'create', state: 'failed' })], 'm', 'w1', T0)).toBeNull()
  expect(jobLine([order({ state: 'succeeded' })], 'm', 'w1', T0)).toBeNull()
})

test('a newer order replaces an older failure; another VM is not touched; an old stop fades', () => {
  const failed = order({ id: 'a', state: 'failed', created_at: '2026-11-03T09:00:00Z', finished_at: '2026-11-03T09:01:00Z' })
  const retry = order({ id: 'b', state: 'running', created_at: '2026-11-03T09:30:00Z', step: 'Deleting' })
  expect(jobLine([failed, retry], 'm', 'w1', T0)?.kind).toBe('working')
  expect(jobLine([failed], 'm', 'w2', T0)).toBeNull()
  expect(jobLine([failed], 'other', 'w1', T0)).toBeNull()
  expect(jobLine([failed], 'm', 'w1', Date.parse('2026-11-03T09:01:00Z') + STOPPED_SHOWN_MS + 1)).toBeNull()
})

test('state words are plain; an unknown state is shown cleaned', () => {
  expect(['queued', 'running', 'succeeded', 'failed', 'timed_out', 'lost_contact'].map(stateWords)).toEqual(['waiting', 'working', 'done', 'failed', 'timed out', 'lost contact'])
  expect(stateWords('odd\u0000state')).toBe('oddstate')
})

test('a create that timed out or lost contact reads as a failed create with its words', () => {
  expect(reasonText(null, 'timed_out')).toBe(TIMED_OUT_TEXT)
  expect(reasonText({}, 'lost_contact')).toBe(LOST_CONTACT_TEXT)
  expect(reasonText({ error: 'no room' }, 'timed_out')).toBe('No room.')
})
