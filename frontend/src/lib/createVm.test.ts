import { test, expect } from 'bun:test'
import { blankForm, kindAfterPick, machineChoices, machineDefaults, machineOptions, pickMachine, preselectedMachine, runtimeCards, startingMachine, unavailableNotes, unavailableSummary } from './createVm.ts'
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

test('a ready machine is pickable and its label says what it runs', () => {
  expect(choice('zed')).toMatchObject({ label: 'zed (VMs and containers)', disabled: false, reason: null })
})

test('the label ends with the free disk when the machine reported it, and a GPU node says so', () => {
  const card = { vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090' }
  const labels = machineChoices([
    machine({ id: 'a', name: 'a', os: 'linux', free_disk_gb: 420.4, capabilities: caps(true, true) }),
    machine({ id: 'b', name: 'b', os: 'linux', free_disk_gb: 55, capabilities: caps(false, true), gpu: [card] }),
    machine({ id: 'c', name: 'c', state: 'offline', free_disk_gb: 10 }),
    machine({ id: 'd', name: 'd', free_disk_gb: null }),
  ]).map((entry) => entry.label)
  expect(labels).toEqual(['a (VMs and containers) — 420GB free', 'b (containers only, gpu node) — 55GB free', 'c (offline) — 10GB free', 'd'])
})

test('the collapsed line counts the machines that cannot take a VM', () => {
  expect(unavailableSummary(3)).toBe("3 machines can't take a VM")
  expect(unavailableSummary(1)).toBe("1 machine can't take a VM")
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

test('the runtime cards grey out the one the picked machine cannot run, with the reason', () => {
  const only = runtimeCards(choice('box'))
  expect(only.map((card) => `${card.kind}:${card.disabled}`)).toEqual(['container:false', 'vm:true'])
  expect(only[1]?.reason).toBe('This machine runs containers only')
  const both = runtimeCards(choice('zed'))
  expect(both.map((card) => card.label)).toEqual(['Container', 'VM'])
  expect(both.map((card) => card.tag)).toEqual(['Recommended', null])
  expect(both.every((card) => !card.disabled && card.reason === null)).toBe(true)
  expect(runtimeCards(undefined).every((card) => !card.disabled)).toBe(true)
})

test('a machine that cannot run containers greys out the Container card', () => {
  const vmOnly = runtimeCards(machineChoices([machine({ id: 'v', name: 'v', capabilities: caps(true, false) })])[0])
  expect(vmOnly.find((card) => card.kind === 'container')).toMatchObject({ disabled: true, reason: 'This machine cannot run containers' })
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

test('with only one machine that can take a VM, the window starts with it', () => {
  const choices = machineChoices([fleet[0]!, fleet[1]!, fleet[2]!])
  expect(startingMachine('/vms/create', null, choices)).toBe('zed')
  expect(startingMachine('/vms/create', null, machineChoices([fleet[1]!]))).toBe('')
})

test('each machine that cannot be picked is explained in a line, with the machine\'s own words when it gave some', () => {
  expect(unavailableNotes(machineChoices(fleet))).toEqual(['none: cannot run VMs or containers', 'off: offline', 'sick: needs setup (the bridge incusbr0 is not trusted)', 'working: busy'])
  expect(unavailableNotes(machineChoices([fleet[0]!]))).toEqual([])
})

test('a new form starts on Medium; a machine set up with other VM sizes starts on Custom with them; sizes equal to a preset pick it', () => {
  expect(blankForm(undefined)).toEqual({ name: '', kind: 'vm', cpu: 2, ramGb: 4, diskGb: 40, size: 'medium', machine: '', bundle: 'blank' })
  const sized = machine({ id: 'm', settings: { vm_cpu: 4, vm_ram_mb: 8192, vm_disk_gb: 80 } })
  expect(blankForm(sized)).toEqual({ name: '', kind: 'vm', cpu: 4, ramGb: 8, diskGb: 80, size: 'custom', machine: 'm', bundle: 'blank' })
  const large = machine({ id: 'm', settings: { vm_cpu: 4, vm_ram_mb: 8192, vm_disk_gb: 60 } })
  expect(blankForm(large)).toMatchObject({ cpu: 4, ramGb: 8, diskGb: 60, size: 'large' })
  expect(machineDefaults(machine({ settings: { vm_cpu: 6 } }))).toEqual({ cpu: 6 })
  expect(machineDefaults(machine())).toEqual({})
})

test('picking another machine fills in its sizes and keeps what was typed', () => {
  const typed = { ...blankForm(undefined), name: 'mine', bundle: 'blank' }
  const sized = machine({ id: 'm', settings: { vm_cpu: 4, vm_ram_mb: 8192, vm_disk_gb: 80 } })
  expect(pickMachine(typed, sized)).toMatchObject({ name: 'mine', machine: 'm', size: 'custom', cpu: 4, ramGb: 8, diskGb: 80 })
  expect(pickMachine({ ...typed, size: 'custom', cpu: 9 }, machine({ id: 'plain' }))).toMatchObject({ size: 'medium', cpu: 2, machine: 'plain' })
})

test('a containers-only machine\'s blank form starts as a container', () => {
  expect(blankForm(fleet[4])).toMatchObject({ kind: 'container', machine: 'box' })
})
