import { test, expect } from 'bun:test'
import { awaitNewVm, parseCreated, type NewVmDeps } from './newVm.ts'
import { command, machine, workload } from './testing.ts'
import type { Command, Machine } from './types.ts'

test('the answer to a create names the order and the machine it went to', () => {
  expect(parseCreated({ command: { id: 'c9', machine: 'mac-mini', state: 'queued' } })).toEqual({ commandId: 'c9', machine: 'mac-mini' })
  for (const answer of [null, 'x', {}, { command: null }, { command: { id: 'c9' } }, { command: { machine: 'm' } }, { command: { id: 3, machine: 'm' } }]) expect(parseCreated(answer), JSON.stringify(answer)).toBeNull()
})

/** Steps the stand-ins through lists of answers, one per call, repeating the last. */
function deps(commands: Command[], fleets: Machine[][], left = false): NewVmDeps & { sleeps: number } {
  let askedCommand = 0
  let askedMachines = 0
  const state = {
    sleeps: 0,
    getCommand: async () => commands[Math.min(askedCommand++, commands.length - 1)] ?? command(),
    listMachines: async () => fleets[Math.min(askedMachines++, fleets.length - 1)] ?? [],
    pause: async () => { state.sleeps++ },
    stopped: () => left,
  }
  return state
}

const made = machine({ id: 'm', workloads: [workload({ id: 'w-7', name: 'build-box' })] })
const created = { commandId: 'c1', machine: 'm' }

test('when the order succeeds and the VM shows on the machine, the VM is ready', async () => {
  const outcome = await awaitNewVm(created, 'build-box', deps([command({ state: 'queued' }), command({ state: 'succeeded' })], [[made]]))
  expect(outcome).toEqual({ kind: 'ready', machine: 'm', workload: 'w-7' })
})

test('a failed order says why in the helper\'s words', async () => {
  const outcome = await awaitNewVm(created, 'build-box', deps([command({ state: 'failed', result: { error: 'no space left' } })], [[made]]))
  expect(outcome).toEqual({ kind: 'failed', message: 'no space left' })
})

test('a failed order without a reason still says something plain', async () => {
  const outcome = await awaitNewVm(created, 'build-box', deps([command({ state: 'failed' })], [[made]]))
  expect(outcome).toEqual({ kind: 'failed', message: 'The machine could not make the VM.' })
})

test('a succeeded order whose VM is not listed yet is waited for', async () => {
  const waiting = deps([command({ state: 'succeeded' })], [[machine({ id: 'm' })], [made]])
  expect(await awaitNewVm(created, 'build-box', waiting)).toEqual({ kind: 'ready', machine: 'm', workload: 'w-7' })
  expect(waiting.sleeps).toBeGreaterThan(0)
})

test('when it takes too long the answer is slow, not a failure', async () => {
  expect(await awaitNewVm(created, 'build-box', deps([command({ state: 'running' })], [[made]]))).toEqual({ kind: 'slow' })
})

test('when the person leaves the page the waiting stops at once', async () => {
  const gone = deps([command({ state: 'succeeded' })], [[made]], true)
  expect(await awaitNewVm(created, 'build-box', gone)).toEqual({ kind: 'slow' })
})

test('a machine that is not on the list never has the VM', async () => {
  expect(await awaitNewVm(created, 'build-box', deps([command({ state: 'succeeded' })], [[machine({ id: 'other' })]]))).toEqual({ kind: 'slow' })
})
