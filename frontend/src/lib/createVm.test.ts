import { test, expect } from 'bun:test'
import { blankForm, kindChoices, kindAfterPick, machineChoices, machineDefaults, machineOptions, preselectedMachine, startingMachine, unavailableNotes } from './createVm.ts'
import { machine } from './testing.ts'

const caps = (vm: boolean, container: boolean) => ({ vm, container, gpu_in_vm: false, gpu_in_container: false })
const problem = { code: 'bridge_blocked_by_firewall', message: 'the bridge incusbr0 is not trusted', fix: 'run setup' }

const fleet = [
  machine({ id: 'zed', name: 'zed', capabilities: caps(true, true) }),
  machine({ id: 'off', name: 'off', state: 'offline', capabilities: caps(true, true) }),
  machine({ id: 'sick', name: 'sick', problems: [problem], capabilities: caps(true, true) }),
  machine({ id: 'working', name: 'working', state: 'busy' }),
  machine({ id: 'box', name: 'box', capabilities: caps(false, true) }),
  machine({ id: 'none', name: 'none', capabilities: caps(false, false) }),
  machine({ id: 'new', name: 'new' }),
]
const choice = (id: string) => machineChoices(fleet).find((entry) => entry.id === id)

test('every machine is listed, sorted by name', () => {
  expect(machineChoices(fleet).map((entry) => entry.id)).toEqual(['box', 'new', 'none', 'off', 'sick', 'working', 'zed'])
})

test('a ready machine is pickable and its label is its name', () => {
  expect(choice('zed')).toMatchObject({ label: 'zed', disabled: false, reason: null })
})

test('an offline machine is disabled and says offline', () => {
  expect(choice('off')).toMatchObject({ label: 'off (offline)', disabled: true, reason: 'offline' })
})

test('a machine with problems is disabled and says it needs setup, with the first problem as the detail', () => {
  expect(choice('sick')).toMatchObject({ label: 'sick (needs setup)', disabled: true, reason: 'needs setup', detail: 'the bridge incusbr0 is not trusted' })
})

test('a busy machine is disabled and says busy', () => {
  expect(choice('working')).toMatchObject({ label: 'working (busy)', disabled: true, reason: 'busy' })
})

test('offline wins over needing setup', () => {
  const both = machineChoices([machine({ id: 'x', name: 'x', state: 'offline', problems: [problem] })])
  expect(both[0]?.reason).toBe('offline')
})

test('a containers-only machine stays pickable but cannot take the VM kind', () => {
  expect(choice('box')).toMatchObject({ label: 'box (containers only)', disabled: false, reason: 'containers only', vm: false, container: true })
})

test('a machine that can run neither kind is disabled', () => {
  expect(choice('none')).toMatchObject({ label: 'none (cannot run VMs or containers)', disabled: true, vm: false, container: false })
})

test('a machine that has not reported what it can run is pickable with both kinds', () => {
  expect(choice('new')).toMatchObject({ label: 'new', disabled: false, vm: true, container: true })
})

test('the kind choices disable the ones the picked machine cannot run, with the reason', () => {
  expect(kindChoices(choice('box'))).toEqual([{ kind: 'vm', label: 'VM (this machine runs containers only)', disabled: true }, { kind: 'container', label: 'Container', disabled: false }])
  expect(kindChoices(choice('zed'))).toEqual([{ kind: 'vm', label: 'VM', disabled: false }, { kind: 'container', label: 'Container', disabled: false }])
  expect(kindChoices(undefined).every((entry) => !entry.disabled)).toBe(true)
})

test('picking a containers-only machine moves a VM form to Container, and leaves a fitting kind alone', () => {
  expect(kindAfterPick(choice('box'), 'vm')).toBe('container')
  expect(kindAfterPick(choice('box'), 'container')).toBe('container')
  expect(kindAfterPick(choice('zed'), 'vm')).toBe('vm')
  expect(kindAfterPick(undefined, 'vm')).toBe('vm')
})

test('the machine in the address is preselected only when it is on the list and can take a VM', () => {
  const choices = machineChoices(fleet)
  expect(preselectedMachine('/vms/create?machine=zed', choices)).toBe('zed')
  expect(preselectedMachine('/vms/create?machine=box', choices)).toBe('box')
  for (const route of ['/vms/create', '/vms/create?machine=off', '/vms/create?machine=gone', '/vms/create?machine=Bad Name', '/machines?machine=zed']) expect(preselectedMachine(route, choices), route).toBe('')
})

test('opened from a machine\'s own page the dropdown lists that machine only, otherwise every machine', () => {
  const choices = machineChoices(fleet)
  expect(machineOptions(choices, null)).toEqual(choices)
  expect(machineOptions(choices, 'zed').map((entry) => entry.id)).toEqual(['zed'])
  expect(machineOptions(choices, 'gone')).toEqual([])
})

test('the window starts with the machine it was opened from, else the pickable one in the address, else none', () => {
  const choices = machineChoices(fleet)
  expect(startingMachine('/vms/create?machine=box', 'zed', choices)).toBe('zed')
  expect(startingMachine('/vms/create?machine=box', null, choices)).toBe('box')
  expect(startingMachine('/vms/create?machine=off', null, choices)).toBe('')
  expect(startingMachine('/vms', null, choices)).toBe('')
})

test('each machine that cannot be picked is explained in a line, with the machine\'s own words when it gave some', () => {
  expect(unavailableNotes(machineChoices(fleet))).toEqual(['none: cannot run VMs or containers', 'off: offline', 'sick: needs setup (the bridge incusbr0 is not trusted)', 'working: busy'])
  expect(unavailableNotes(machineChoices([fleet[0]!]))).toEqual([])
})

test('a new form has the usual defaults; a machine set up with VM sizes gives them', () => {
  expect(blankForm(undefined)).toEqual({ name: '', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: '', bundle: 'blank' })
  const sized = machine({ id: 'm', settings: { vm_cpu: 4, vm_ram_mb: 8192, vm_disk_gb: 80 } })
  expect(blankForm(sized)).toEqual({ name: '', kind: 'vm', cpu: 4, ramGb: 8, diskGb: 80, machine: 'm', bundle: 'blank' })
  expect(machineDefaults(machine({ settings: { vm_cpu: 6 } }))).toEqual({ cpu: 6 })
  expect(machineDefaults(machine())).toEqual({})
})

test('a containers-only machine\'s blank form starts as a container', () => {
  expect(blankForm(fleet[4])).toMatchObject({ kind: 'container', machine: 'box' })
})
