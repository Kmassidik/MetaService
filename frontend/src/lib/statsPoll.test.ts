import { expect, test } from 'bun:test'
import { startPolling, type PollEnvironment } from './statsPoll.ts'

function fakeEnvironment() {
  let visible = true
  let listener: () => void = () => {}
  let next = 1
  const timers = new Map<number, () => void>()
  const environment: PollEnvironment = {
    isVisible: () => visible,
    onVisibilityChange: (callback) => { listener = callback; return () => { listener = () => {} } },
    setTimer: (run) => { const id = next++; timers.set(id, run); return id },
    clearTimer: (id) => { timers.delete(id) },
  }
  return {
    environment, timers,
    setVisible(value: boolean) { visible = value; listener() },
    fire() { const [id, run] = [...timers][0] ?? []; if (id !== undefined && run) { timers.delete(id); run() } },
  }
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

test('it asks at once, then again after each timer', async () => {
  const world = fakeEnvironment()
  let calls = 0
  const stop = startPolling(world.environment, 5000, async () => { calls += 1 })
  await settle()
  expect(calls).toBe(1)
  expect(world.timers.size).toBe(1)
  world.fire()
  await settle()
  expect(calls).toBe(2)
  stop()
  expect(world.timers.size).toBe(0)
})

test('a hidden tab stops asking and a visible one asks at once', async () => {
  const world = fakeEnvironment()
  let calls = 0
  const stop = startPolling(world.environment, 5000, async () => { calls += 1 })
  await settle()
  world.setVisible(false)
  expect(world.timers.size).toBe(0)
  await settle()
  expect(calls).toBe(1)
  world.setVisible(true)
  await settle()
  expect(calls).toBe(2)
  expect(world.timers.size).toBe(1)
  stop()
})

test('a tab that starts hidden does not ask until it is shown', async () => {
  const world = fakeEnvironment()
  world.setVisible(false)
  let calls = 0
  const stop = startPolling(world.environment, 5000, async () => { calls += 1 })
  await settle()
  expect(calls).toBe(0)
  world.setVisible(true)
  await settle()
  expect(calls).toBe(1)
  stop()
})

test('a slow answer is never overlapped by the next ask', async () => {
  const world = fakeEnvironment()
  let calls = 0
  let release: () => void = () => {}
  const stop = startPolling(world.environment, 5000, () => { calls += 1; return new Promise<void>((resolve) => { release = resolve }) })
  await settle()
  world.setVisible(true)
  await settle()
  expect(calls).toBe(1)
  release()
  await settle()
  expect(world.timers.size).toBe(1)
  stop()
})

test('the wait is asked before each run, and a null wait pauses until the tab is shown again', async () => {
  const world = fakeEnvironment()
  let calls = 0
  let wait: number | null = 2000
  const waits: number[] = []
  const environment: PollEnvironment = { ...world.environment, setTimer: (run, ms) => { waits.push(ms); return world.environment.setTimer(run, ms) } }
  const stop = startPolling(environment, () => wait, async () => { calls += 1 })
  await settle()
  expect(waits).toEqual([2000])
  wait = 5000
  world.fire()
  await settle()
  expect(waits).toEqual([2000, 5000])
  wait = null
  world.fire()
  await settle()
  expect(calls).toBe(3)
  expect(world.timers.size).toBe(0)
  world.setVisible(true)
  await settle()
  expect(calls).toBe(4)
  stop()
})
