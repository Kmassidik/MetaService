import { test, expect } from 'bun:test'
import { consoleTitle, terminalAccess } from './terminalAccess.ts'
import { machine, workload } from './testing.ts'

test('a running VM on a Mac online can open a terminal', () => {
  expect(terminalAccess(machine(), workload())).toEqual({ allowed: true })
})

test('a stopped VM says it is stopped', () => {
  expect(terminalAccess(machine(), workload({ state: 'stopped' }))).toEqual({ allowed: false, text: 'VM is stopped', title: 'The terminal opens when the VM is running. Start the VM first.' })
})

test('a VM that is not running for another reason says it is not running', () => {
  for (const state of ['provisioning', 'failed', 'deleting']) {
    expect(terminalAccess(machine(), workload({ state })), state).toMatchObject({ allowed: false, text: 'VM is not running' })
  }
})

test('only Mac machines have a terminal for now, and that wins over the VM being stopped', () => {
  const linux = machine({ os: 'linux', arch: 'x86_64' })
  expect(terminalAccess(linux, workload())).toEqual({ allowed: false, text: 'Mac machines only for now', title: 'The console is only available on Mac machines for now.' })
  expect(terminalAccess(linux, workload({ state: 'stopped' }))).toMatchObject({ text: 'Mac machines only for now' })
})

test('an offline Mac cannot be reached', () => {
  expect(terminalAccess(machine({ state: 'offline' }), workload())).toMatchObject({ allowed: false, text: 'Machine is offline' })
})

test('the window is titled with the VM name, or its id when it has none', () => {
  expect(consoleTitle(workload({ id: 'w-1', name: 'box' }))).toBe('box')
  expect(consoleTitle(workload({ id: 'w-1', name: '' }))).toBe('w-1')
})
