import { expect, test } from 'bun:test'
import { createAction, lineOf, type ActionClock, type ActionView } from './action.ts'
import { FAILED_MESSAGE, MIN_BUSY_MS, REQUEST_TIMEOUT_MS, SUCCESS_LINE_MS, TIMEOUT_MESSAGE } from './timeouts.ts'

/** A clock the test moves by hand. */
function fakeClock() {
  let now = 0
  let tasks: { at: number; run: () => void; live: boolean }[] = []
  const clock: ActionClock = {
    now: () => now,
    after(ms, run) {
      const task = { at: now + ms, run, live: true }
      tasks.push(task)
      return () => { task.live = false }
    },
  }
  const settle = async () => { for (let i = 0; i < 8; i++) await Promise.resolve() }
  async function advance(ms: number) {
    const end = now + ms
    await settle()
    for (;;) {
      const due = tasks.filter((task) => task.live && task.at <= end).sort((a, b) => a.at - b.at)[0]
      if (!due) break
      now = due.at
      due.live = false
      due.run()
      await settle()
    }
    now = end
    tasks = tasks.filter((task) => task.live)
  }
  return { clock, advance }
}

function deferred() {
  let resolve: (value?: unknown) => void = () => {}
  const promise = new Promise((ok) => { resolve = ok })
  return { promise, resolve }
}

test('starts idle', () => {
  const { clock } = fakeClock()
  expect(createAction({ clock }).view()).toEqual({ status: 'idle', message: '' })
})

test('a second run while busy does nothing and gives the same promise', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  const gate = deferred()
  let calls = 0
  const work = () => { calls += 1; return gate.promise }
  const first = action.run(work)
  const second = action.run(work)
  expect(second).toBe(first)
  expect(action.view().status).toBe('busy')
  gate.resolve()
  await advance(MIN_BUSY_MS)
  await first
  expect(calls).toBe(1)
})

test('stays busy for the minimum time even when the work is instant', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  void action.run(async () => 'ok')
  await advance(MIN_BUSY_MS - 1)
  expect(action.view().status).toBe('busy')
  await advance(1)
  expect(action.view().status).toBe('done')
})

test('does not add waiting when the work already took longer than the minimum', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  const gate = deferred()
  void action.run(() => gate.promise)
  await advance(MIN_BUSY_MS * 3)
  gate.resolve()
  await advance(0)
  expect(action.view().status).toBe('done')
})

test('done goes back to idle after the success line time', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  void action.run(async () => undefined)
  await advance(MIN_BUSY_MS)
  expect(action.view().status).toBe('done')
  await advance(SUCCESS_LINE_MS - 1)
  expect(action.view().status).toBe('done')
  await advance(1)
  expect(action.view().status).toBe('idle')
})

test('a failure keeps the plain message and frees the action; it never throws', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  const run = action.run(async () => { throw new Error('No room on that machine') })
  await advance(MIN_BUSY_MS)
  await run
  expect(action.view()).toEqual({ status: 'failed', message: 'No room on that machine' })
  void action.run(async () => undefined)
  expect(action.view().status).toBe('busy')
})

test('a failure that is not an Error gets the plain fallback', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  void action.run(async () => { throw 'nope' })
  await advance(MIN_BUSY_MS)
  expect(action.view().message).toBe(FAILED_MESSAGE)
})

test('work that throws before it returns a promise is a failure too', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  void action.run(() => { throw new Error('early') })
  await advance(MIN_BUSY_MS)
  expect(action.view()).toEqual({ status: 'failed', message: 'early' })
})

test('a hung request is freed by the timeout with the plain message', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  const run = action.run(() => new Promise(() => {}))
  await advance(REQUEST_TIMEOUT_MS - 1)
  expect(action.view().status).toBe('busy')
  await advance(1)
  await run
  expect(action.view()).toEqual({ status: 'failed', message: TIMEOUT_MESSAGE })
})

test('a longer timeout can be asked for', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock, timeoutMs: REQUEST_TIMEOUT_MS * 2 })
  void action.run(() => new Promise(() => {}))
  await advance(REQUEST_TIMEOUT_MS * 2 - 1)
  expect(action.view().status).toBe('busy')
  await advance(1)
  expect(action.view().message).toBe(TIMEOUT_MESSAGE)
})

test('an answer that comes after the timeout changes nothing', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  const gate = deferred()
  void action.run(() => gate.promise)
  await advance(REQUEST_TIMEOUT_MS)
  gate.resolve()
  await advance(0)
  expect(action.view().status).toBe('failed')
})

test('a new run is not cut short by the old success timer', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  void action.run(async () => undefined)
  await advance(MIN_BUSY_MS + SUCCESS_LINE_MS - 100)
  const gate = deferred()
  void action.run(() => gate.promise)
  expect(action.view().status).toBe('busy')
  await advance(200)
  expect(action.view().status).toBe('busy')
})

test('listeners hear every change and can stop listening', async () => {
  const { clock, advance } = fakeClock()
  const action = createAction({ clock })
  const seen: ActionView['status'][] = []
  const stop = action.subscribe((view) => seen.push(view.status))
  void action.run(async () => undefined)
  await advance(MIN_BUSY_MS + SUCCESS_LINE_MS)
  expect(seen).toEqual(['busy', 'done', 'idle'])
  stop()
  void action.run(async () => undefined)
  expect(seen).toHaveLength(3)
})

test('the line next to the button is the failure, the success text, or nothing', () => {
  expect(lineOf({ status: 'failed', message: 'No room' }, 'Started')).toBe('No room')
  expect(lineOf({ status: 'done', message: '' }, 'Started')).toBe('Started')
  expect(lineOf({ status: 'busy', message: '' }, 'Started')).toBe('')
  expect(lineOf({ status: 'idle', message: '' }, 'Started')).toBe('')
})
