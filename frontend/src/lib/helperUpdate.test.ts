import { expect, test } from 'bun:test'
import { failureView, helperView, listTag, outcomeView, parseHelperUpdate, parseUpdateResult, shortBuild, UPDATING_TEXT } from './helperUpdate.ts'
import { UnreadableAnswer } from './machineDetail.ts'
import { machine } from './testing.ts'

const OLD = 'a'.repeat(64)
const NEW = 'b'.repeat(64)
const info = (extra = {}) => ({ available: true, current_build: OLD, newest_build: NEW, reason: null, ...extra })

test('a build is shown as its first 8 characters, and a missing one says so', () => {
  expect(shortBuild(OLD)).toBe('aaaaaaaa')
  expect(shortBuild(null)).toBe('not reported')
  expect(shortBuild(undefined)).toBe('not reported')
  expect(shortBuild('')).toBe('not reported')
})

test('a different build can be updated while the machine is online', () => {
  const view = helperView(machine({ agent_build: OLD, update: info() }))
  expect(view).toMatchObject({ build: 'aaaaaaaa', status: 'available', label: 'Update available', canUpdate: true, note: null })
})

test('the same build is up to date and there is nothing to press', () => {
  const view = helperView(machine({ agent_build: NEW, update: info({ available: false, current_build: NEW }) }))
  expect(view).toMatchObject({ status: 'up_to_date', label: 'Up to date', canUpdate: false })
})

test('an old helper that does not say its build is unknown but can still be updated', () => {
  const view = helperView(machine({ agent_build: null, update: info({ current_build: null }) }))
  expect(view).toMatchObject({ build: 'not reported', status: 'unknown', label: 'Unknown (old helper)', canUpdate: true })
})

test('an offline machine cannot be updated and says why', () => {
  const view = helperView(machine({ state: 'offline', agent_build: OLD, update: info() }))
  expect(view.canUpdate).toBe(false)
  expect(view.note).toBe('The machine is offline.')
})

test('a machine the parent has no program for cannot be updated and shows the parent reason as text', () => {
  const reason = 'The parent has no MetaService program for this kind of computer, so its helper cannot be updated from here.'
  const view = helperView(machine({ agent_build: OLD, update: info({ available: false, newest_build: null, reason }) }))
  expect(view).toMatchObject({ status: 'cannot', label: 'Cannot be updated from here', canUpdate: false, note: reason })
})

test('a parent that does not send an update answer is unknown and offers nothing', () => {
  expect(helperView(machine({ agent_build: OLD }))).toMatchObject({ status: 'unknown', canUpdate: false })
})

test('the list tag shows only when an update is available', () => {
  expect(listTag(machine({ update: info() }))).toBe('Update available')
  expect(listTag(machine({ update: info({ available: false }) }))).toBeNull()
  expect(listTag(machine())).toBeNull()
})

test('the update answer is read strictly', () => {
  expect(parseHelperUpdate({ available: true, current_build: null, newest_build: NEW, reason: null })).toEqual({ available: true, current_build: null, newest_build: NEW, reason: null })
  expect(parseHelperUpdate(undefined)).toBeUndefined()
  for (const bad of [null, 'yes', [], { available: 'yes', current_build: null, newest_build: null, reason: null }, { available: true, current_build: 5, newest_build: null, reason: null },
    { available: true, current_build: null, newest_build: {}, reason: null }, { available: true, current_build: null, newest_build: null, reason: 7 }]) {
    expect(() => parseHelperUpdate(bad)).toThrow(UnreadableAnswer)
  }
})

test('the result of an update is read strictly', () => {
  expect(parseUpdateResult({ result: 'updated', message: 'done' })).toEqual({ result: 'updated', message: 'done' })
  for (const bad of [null, {}, { result: 'maybe', message: 'x' }, { result: 'updated' }, { result: 'updated', message: 5 }, 'updated']) {
    expect(() => parseUpdateResult(bad)).toThrow(UnreadableAnswer)
  }
})

test('each result has a title and tone, and the parent sentence is the detail', () => {
  expect(outcomeView({ result: 'updated', message: 'it is running' })).toEqual({ tone: 'ok', title: 'Updated', detail: 'it is running' })
  expect(outcomeView({ result: 'rolled_back', message: 'old one is back' })).toEqual({ tone: 'warn', title: 'Rolled back', detail: 'old one is back' })
  expect(outcomeView({ result: 'failed', message: 'checksum' })).toEqual({ tone: 'bad', title: 'Update failed', detail: 'checksum' })
})

test('a refusal is told in plain words', () => {
  expect(failureView('login_needed', 'cannot log in')).toEqual({ tone: 'warn', title: 'Login needed', detail: 'cannot log in' })
  expect(failureView('machine_busy', 'busy')).toMatchObject({ tone: 'warn', title: 'Not now' })
  expect(failureView('up_to_date', 'newest')).toMatchObject({ tone: 'ok', title: 'Already up to date' })
  expect(failureView('unreachable', 'down')).toEqual({ tone: 'bad', title: 'Update failed', detail: 'down' })
})

test('hostile text stays text: it is only ever returned, never turned into markup', () => {
  const hostile = '<img src=x onerror=alert(1)><script>window.pwned=1</script>'
  expect(outcomeView({ result: 'failed', message: hostile }).detail).toBe(hostile)
  expect(helperView(machine({ agent_build: OLD, update: info({ available: false, newest_build: null, reason: hostile }) })).note).toBe(hostile)
  expect(shortBuild(hostile + OLD)).toBe(hostile.slice(0, 8))
})

test('the progress text is fixed', () => {
  expect(UPDATING_TEXT).toBe('Updating…')
})
