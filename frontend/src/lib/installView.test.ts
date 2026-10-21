import { expect, test } from 'bun:test'
import { formatElapsed, installProgress, installTitle, stepWord } from './installView.ts'
import { ringArc } from './ring.ts'
import type { InstallJob, InstallStep, StepState } from './types.ts'

const step = (id: string, state: StepState): InstallStep => ({ id, label: `Step ${id}`, state })
const job = (states: StepState[], state: InstallJob['state'] = 'running'): InstallJob => ({ id: 'j1', name: 'rtx-pc', state, steps: states.map((value, index) => step(String(index + 1), value)) })

test('progress counts the done steps and names the step that is running', () => {
  expect(installProgress(job(['done', 'done', 'running', 'pending']))).toEqual({ done: 2, total: 4, current: 3 })
  expect(installProgress(job(['pending', 'pending']))).toEqual({ done: 0, total: 2, current: null })
  expect(installProgress(job(['done', 'done'], 'done'))).toEqual({ done: 2, total: 2, current: null })
})

test('progress names the step that failed', () => {
  expect(installProgress(job(['done', 'failed', 'pending'], 'failed'))).toEqual({ done: 1, total: 3, current: 2 })
})

test('the title follows the job: installing, stopped at a step, online', () => {
  expect(installTitle(job(['done', 'running']))).toBe('Installing rtx-pc')
  expect(installTitle(job(['done', 'failed'], 'failed'))).toBe('Stopped at step 2')
  expect(installTitle(job(['pending', 'pending'], 'failed'))).toBe('The install stopped')
  expect(installTitle(job(['done', 'done'], 'done'))).toBe('rtx-pc is online')
})

test('every step state has a word for people who cannot see the mark', () => {
  const states: StepState[] = ['pending', 'running', 'done', 'failed']
  expect(states.map(stepWord)).toEqual(['Waiting', 'Running', 'Done', 'Failed'])
})

test('the elapsed time is minutes and two-digit seconds', () => {
  expect(formatElapsed(0)).toBe('0:00')
  expect(formatElapsed(42_000)).toBe('0:42')
  expect(formatElapsed(151_900)).toBe('2:31')
  expect(formatElapsed(-5)).toBe('0:00')
  expect(formatElapsed(3_600_000)).toBe('60:00')
})

test('the ring arc is the done share of the circle, and an empty ring has none', () => {
  const circle = 2 * Math.PI * 38
  expect(ringArc(0, 9)).toEqual({ filled: 0, circle })
  expect(ringArc(9, 9).filled).toBeCloseTo(circle, 5)
  expect(ringArc(9, 18).filled).toBeCloseTo(circle / 2, 5)
  expect(ringArc(0, 0).filled).toBe(0)
  expect(ringArc(12, 9).filled).toBeCloseTo(circle, 5)
})
