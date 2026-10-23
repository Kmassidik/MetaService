import { expect, test } from 'bun:test'
import { createProgress, progressView, workloadOf } from './createProgress.ts'
import { command, machine, workload } from './testing.ts'

const states = (progress: ReturnType<typeof createProgress>) => progress.steps.map((step) => step.state)
const labels = (progress: ReturnType<typeof createProgress>) => progress.steps.map((step) => step.label)
const made = (state: string, extra: Parameters<typeof workload>[0] = {}) => machine({ workloads: [workload({ id: 'w-1', name: 'box', state, ...extra })] })
const order = (extra: Parameters<typeof command>[0] = {}) => command({ params: { name: 'box', kind: 'vm' }, ...extra })
const succeeded = (extra: Parameters<typeof command>[0] = {}) => order({ state: 'succeeded', result: { workload_id: 'w-1' }, ...extra })

test('a queued order waits for the machine', () => {
  const progress = createProgress(order({ state: 'queued' }), machine())
  expect(states(progress)).toEqual(['now', 'next', 'next'])
  expect(progress).toMatchObject({ status: 'working', reason: null })
  expect(labels(progress)).toEqual(['Waiting for the machine', 'Creating', 'Starting'])
})

test('an order that is not known yet counts as waiting', () => {
  expect(states(createProgress(undefined, undefined))).toEqual(['now', 'next', 'next'])
})

test('a running order is being created', () => {
  expect(states(createProgress(order({ state: 'running' }), machine()))).toEqual(['done', 'now', 'next'])
})

test('a made VM that the machine has not listed yet is starting', () => {
  expect(states(createProgress(succeeded(), machine()))).toEqual(['done', 'done', 'now'])
})

test('a VM the machine lists as being made is starting too', () => {
  for (const state of ['provisioning', 'creating', 'starting']) {
    expect(states(createProgress(succeeded(), made(state)))).toEqual(['done', 'done', 'now'])
  }
})

test('a running VM without an app is ready, with every step done', () => {
  const progress = createProgress(succeeded(), made('running'))
  expect(states(progress)).toEqual(['done', 'done', 'done'])
  expect(progress).toMatchObject({ status: 'ready', reason: null })
})

test('a failed order fails the Creating step with the helper reason in a sentence', () => {
  const progress = createProgress(order({ state: 'failed', result: { error: 'no space left' } }), machine())
  expect(states(progress)).toEqual(['done', 'failed', 'next'])
  expect(progress).toMatchObject({ status: 'failed', reason: 'No space left.' })
})

test('a failed order without a reason still says something', () => {
  expect(createProgress(order({ state: 'failed' }), machine()).reason).toBe('The machine could not make the VM.')
})

test('a VM that stopped right after it was made fails the Starting step with the reason it gave', () => {
  const stopped = made('stopped', { stopped_reason: { exit_code: 255, log_tail: 'Failed to mount API filesystems.' } })
  const progress = createProgress(succeeded(), stopped)
  expect(states(progress)).toEqual(['done', 'done', 'failed'])
  expect(progress).toMatchObject({ status: 'failed', reason: 'Failed to mount API filesystems.' })
})

test('a VM that stopped without a reason fails Starting with a plain sentence', () => {
  const progress = createProgress(succeeded(), made('failed'))
  expect(states(progress)).toEqual(['done', 'done', 'failed'])
  expect(progress.reason).toBe('The VM was made but stopped right after it started.')
})

test('a chosen app adds a fourth step, which waits until the VM runs', () => {
  const withApp = order({ state: 'running', params: { name: 'box', app: 'openclaw' } })
  const progress = createProgress(withApp, machine())
  expect(labels(progress)).toEqual(['Waiting for the machine', 'Creating', 'Starting', 'Installing OpenClaw'])
  expect(states(progress)).toEqual(['done', 'now', 'next', 'next'])
  const starting = createProgress({ ...withApp, state: 'succeeded', result: { workload_id: 'w-1' } }, made('provisioning'))
  expect(states(starting)).toEqual(['done', 'done', 'now', 'next'])
})

test('once the VM runs the app step is current, also before the machine has reported the app', () => {
  const withApp = succeeded({ params: { name: 'box', app: 'hermes' } })
  expect(states(createProgress(withApp, made('running')))).toEqual(['done', 'done', 'done', 'now'])
  expect(states(createProgress(withApp, made('running', { app: { name: 'hermes', state: 'installing', message: null } })))).toEqual(['done', 'done', 'done', 'now'])
})

test('a ready app finishes the list', () => {
  const progress = createProgress(succeeded({ params: { name: 'box', app: 'hermes' } }), made('running', { app: { name: 'hermes', state: 'ready', message: null } }))
  expect(states(progress)).toEqual(['done', 'done', 'done', 'done'])
  expect(progress.status).toBe('ready')
})

test('a failed app install fails the app step with its message, or a plain sentence', () => {
  const failed = (message: string | null) => createProgress(succeeded({ params: { name: 'box', app: 'openclaw' } }), made('running', { app: { name: 'openclaw', state: 'failed', message } }))
  expect(states(failed('No internet in the VM.'))).toEqual(['done', 'done', 'done', 'failed'])
  expect(failed('No internet in the VM.')).toMatchObject({ status: 'failed', reason: 'No internet in the VM.' })
  expect(failed(null).reason).toBe('The app could not be installed.')
})

test('the app is also known from the machine when the order does not carry it', () => {
  const progress = createProgress(succeeded(), made('running', { app: { name: 'hermes', state: 'installing', message: null } }))
  expect(labels(progress)[3]).toBe('Installing Hermes')
})

test('a failed create never shows the app step as current', () => {
  const progress = createProgress(order({ state: 'failed', params: { name: 'box', app: 'openclaw' }, result: { error: 'x' } }), machine())
  expect(states(progress)).toEqual(['done', 'failed', 'next', 'next'])
})

test('the VM is found by id, and before that by name while it is being made; a running VM of the same name is another VM', () => {
  expect(workloadOf(succeeded(), made('running'))?.id).toBe('w-1')
  expect(workloadOf(order({ state: 'running' }), made('provisioning'))?.id).toBe('w-1')
  expect(workloadOf(order({ state: 'running' }), made('running'))).toBeNull()
  expect(workloadOf(undefined, made('running'))).toBeNull()
})

test('the view names the VM, its machine, its kind, its logo and its id', () => {
  const home = machine({ id: 'm', name: 'Studio', workloads: [workload({ id: 'w-1', name: 'box', state: 'running' })] })
  const view = progressView([succeeded({ params: { name: 'box', kind: 'container', app: 'openclaw' } })], [home], 'c1')
  expect(view?.header).toEqual({ name: 'box', machineId: 'm', machineName: 'Studio', kind: 'container', app: 'openclaw', logo: 'openclaw', workloadId: 'w-1' })
})

test('the view falls back to the machine id, a plain name and the VM kind, and has no VM id before one is known', () => {
  const view = progressView([command({ state: 'queued', params: {} })], [], 'c1')
  expect(view?.header).toEqual({ name: 'new VM', machineId: 'm', machineName: 'm', kind: 'vm', app: null, logo: null, workloadId: null })
})

test('nothing is shown when no order is watched or the watched one is not known', () => {
  expect(progressView([order()], [], null)).toBeNull()
  expect(progressView([order()], [], 'other')).toBeNull()
})
