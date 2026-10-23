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

const CAPS = { vm: false, container: true, gpu_in_vm: false, gpu_in_container: false }
const UPDATE_TEXT = 'Update the helper to use the terminal'
const linux = (terminal?: boolean) => machine({ os: 'linux', arch: 'x86_64', capabilities: terminal === undefined ? CAPS : { ...CAPS, terminal } })

test('a Linux machine whose helper says terminal can open a terminal in a container', () => {
  expect(terminalAccess(linux(true), workload({ kind: 'container' }))).toEqual({ allowed: true })
})

test('a Linux machine without the flag says to update the helper, and that wins over the container being stopped', () => {
  for (const flag of [undefined, false]) {
    expect(terminalAccess(linux(flag), workload({ kind: 'container' })), String(flag)).toEqual({ allowed: false, text: UPDATE_TEXT, title: 'Update the helper on this machine to use the terminal.' })
  }
  expect(terminalAccess(linux(false), workload({ kind: 'container', state: 'stopped' }))).toMatchObject({ text: UPDATE_TEXT })
})

test('a Linux machine with no capabilities at all (never reported) says to update the helper', () => {
  expect(terminalAccess(machine({ os: 'linux', arch: 'x86_64' }), workload({ kind: 'container' }))).toMatchObject({ allowed: false, text: UPDATE_TEXT })
})

test('an old Mac helper without the flag keeps its terminal', () => {
  expect(terminalAccess(machine({ capabilities: CAPS }), workload())).toEqual({ allowed: true })
  expect(terminalAccess(machine({ capabilities: { ...CAPS, terminal: false } }), workload())).toEqual({ allowed: true })
})

test('a VM on a Linux machine is off with "Containers only for now", even when the helper has a console', () => {
  expect(terminalAccess(linux(true), workload({ kind: 'vm' }))).toEqual({ allowed: false, text: 'Containers only for now', title: 'The terminal works in containers for now. A VM on a Linux machine has not been tried yet.' })
})

test('a VM on a Mac with the flag still opens', () => {
  expect(terminalAccess(machine({ capabilities: { ...CAPS, terminal: true } }), workload({ kind: 'vm' }))).toEqual({ allowed: true })
})

test('an offline Linux machine with a console says it is offline; a stopped or starting container says so', () => {
  expect(terminalAccess({ ...linux(true), state: 'offline' }, workload({ kind: 'container' }))).toMatchObject({ text: 'Machine is offline' })
  expect(terminalAccess(linux(true), workload({ kind: 'container', state: 'stopped' }))).toMatchObject({ text: 'VM is stopped' })
  expect(terminalAccess(linux(true), workload({ kind: 'container', state: 'provisioning' }))).toMatchObject({ text: 'VM is not running' })
})

test('an offline Mac cannot be reached', () => {
  expect(terminalAccess(machine({ state: 'offline' }), workload())).toMatchObject({ allowed: false, text: 'Machine is offline' })
})

test('the window is titled with the VM name, or its id when it has none', () => {
  expect(consoleTitle(workload({ id: 'w-1', name: 'box' }))).toBe('box')
  expect(consoleTitle(workload({ id: 'w-1', name: '' }))).toBe('w-1')
})
