import { test, expect } from 'bun:test'
import { coresPerSocket, cpuAfterChange, cpuFields, cpuNote, cpuOffer, cpuProblem, flagMachines, flagSetting, limitPercent, modelVendor, totalFromCores, totalFromSockets, withFlag, HOST_VENDOR, MAC_CPU_NOTE, MAC_LIMIT_NOTE, OLD_HELPER_CPU_NOTE, OLD_HELPER_LIMIT_NOTE, ONE_SOCKET_TEXT, SOCKETS_TEXT, WHOLE_CORES_TEXT } from './cpuOptions.ts'
import { machine } from './testing.ts'
import type { WorkloadForm } from './types.ts'
import { matchingSize } from './vmSize.ts'

const kinds = { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }
const linux = machine({ id: 'rtx', name: 'PC-RTX-5090', os: 'linux', arch: 'x86_64', capabilities: { ...kinds, cpu_models: ['host', 'EPYC-Genoa', 'Skylake-Server'], cpu_topology: true, cpu_flags: ['nested-virt', 'aes'], cpu_limit: true } })
const oldHelper = machine({ id: 'old', name: 'old-pc', os: 'linux', arch: 'x86_64', capabilities: kinds })
const mac = machine({ id: 'mac', name: 'Mac-studio', os: 'macos', capabilities: kinds })
const vm = (extra: Partial<WorkloadForm> = {}): WorkloadForm => ({ name: 'demo', kind: 'vm', cpu: 4, ramGb: 4, diskGb: 40, ...extra })

test('a machine that says nothing offers the host CPU on one socket, no flags and no limit, as before', () => {
  for (const each of [oldHelper, mac, undefined]) expect(cpuOffer(each)).toEqual({ models: ['host'], sockets: false, flags: [], limit: false })
})

test('a machine that says what it can offers exactly that, host first and the flags in the table order', () => {
  expect(cpuOffer(linux)).toEqual({ models: ['host', 'EPYC-Genoa', 'Skylake-Server'], sockets: true, flags: ['nested-virt', 'aes'], limit: true })
  const shuffled = machine({ capabilities: { ...kinds, cpu_models: ['EPYC', 'host'], cpu_flags: ['aes', 'nested-virt', 'avx512'] } })
  expect(cpuOffer(shuffled).models).toEqual(['host', 'EPYC'])
  expect(cpuOffer(shuffled).flags).toEqual(['nested-virt', 'aes'])
})

test('the vendor column', () => {
  expect(modelVendor('host')).toBe(HOST_VENDOR)
  for (const model of ['EPYC', 'EPYC-Genoa', 'EPYC-Rome-v2', 'Opteron_G5']) expect(modelVendor(model)).toBe('AMD')
  for (const model of ['Skylake-Server', 'SapphireRapids', 'Icelake-Server', 'Haswell', 'Cascadelake-Server']) expect(modelVendor(model)).toBe('Intel')
  for (const model of ['kvm64', 'qemu64']) expect(modelVendor(model)).toBe('Generic')
  expect(modelVendor('cortex-a72')).toBe('Other')
})

test('the note under the CPU fields says why there is no choice, a Mac in its own words', () => {
  expect(cpuNote(oldHelper, 'vm', cpuOffer(oldHelper))).toBe(OLD_HELPER_CPU_NOTE)
  expect(cpuNote(mac, 'vm', cpuOffer(mac))).toBe(MAC_CPU_NOTE)
  expect(cpuNote(oldHelper, 'container', cpuOffer(oldHelper))).toBe(OLD_HELPER_LIMIT_NOTE)
  expect(cpuNote(mac, 'container', cpuOffer(mac))).toBe(MAC_LIMIT_NOTE)
  expect(cpuNote(linux, 'vm', cpuOffer(linux))).toBeNull()
  expect(cpuNote(linux, 'container', cpuOffer(linux))).toBeNull()
  expect(cpuNote(undefined, 'vm', cpuOffer(undefined))).toBeNull()
  const typesOnly = machine({ os: 'linux', capabilities: { ...kinds, cpu_models: ['host', 'EPYC'] } })
  expect(cpuNote(typesOnly, 'vm', cpuOffer(typesOnly))).toBeNull()
})

test('Cores is the total over the sockets, and Cores or Sockets moving moves the total', () => {
  expect(coresPerSocket(vm({ cpu: 8, cpuSockets: 2 }))).toBe(4)
  expect(coresPerSocket(vm({ cpu: 4 }))).toBe(4)
  expect(coresPerSocket(vm({ cpu: '', cpuSockets: 2 }))).toBe('')
  expect(coresPerSocket(vm({ cpu: 4, cpuSockets: 'x' }))).toBe(4)
  expect(totalFromCores('3', vm({ cpuSockets: 2 }))).toBe(6)
  expect(totalFromCores('', vm({ cpuSockets: 2 }))).toBe('')
  expect(totalFromCores('abc', vm())).toBe('abc')
  expect(totalFromSockets('2', vm({ cpu: 4 }))).toBe(8)
  expect(totalFromSockets('1', vm({ cpu: 8, cpuSockets: 2 }))).toBe(4)
  expect(totalFromSockets('', vm({ cpu: 8, cpuSockets: 2 }))).toBe(8)
  expect(totalFromSockets('0', vm({ cpu: 8, cpuSockets: 2 }))).toBe(8)
})

test('the limit is sent in percent of one core', () => {
  expect(limitPercent('1.5')).toBe(150)
  expect(limitPercent(0.25)).toBe(25)
  expect(limitPercent('')).toBeNull()
  expect(limitPercent(undefined)).toBeNull()
  expect(limitPercent('lots')).toBeNull()
})

test('problems: sockets, whole cores, a type or flag the machine does not offer, a limit out of range', () => {
  const offer = cpuOffer(linux)
  expect(cpuProblem(vm({ cpu: 8, cpuSockets: 2, cpuType: 'EPYC-Genoa', cpuFlags: { aes: 'on' } }), offer)).toBeNull()
  expect(cpuProblem(vm({ cpuSockets: 9 }), offer)).toBe(SOCKETS_TEXT)
  expect(cpuProblem(vm({ cpuSockets: 0 }), offer)).toBe(SOCKETS_TEXT)
  expect(cpuProblem(vm({ cpuSockets: 1.5 }), offer)).toBe(SOCKETS_TEXT)
  expect(cpuProblem(vm({ cpu: 5, cpuSockets: 2 }), offer)).toBe(WHOLE_CORES_TEXT)
  expect(cpuProblem(vm({ cpuSockets: 2 }), cpuOffer(oldHelper))).toBe(ONE_SOCKET_TEXT)
  expect(cpuProblem(vm({ cpuType: 'EPYC-Genoa' }), cpuOffer(oldHelper))).toBe('This machine cannot give a VM the EPYC-Genoa CPU.')
  expect(cpuProblem(vm({ cpuFlags: { 'nested-virt': 'off' } }), cpuOffer(mac))).toBe('This machine cannot switch the nested-virt flag.')
  const container = vm({ kind: 'container', cpu: 2 })
  expect(cpuProblem({ ...container, cpuLimit: '1.5' }, offer)).toBeNull()
  expect(cpuProblem({ ...container, cpuLimit: '' }, offer)).toBeNull()
  expect(cpuProblem({ ...container, cpuLimit: '3' }, offer)).toBe('CPU limit must be between 0.1 and 2 cores, or empty for no limit.')
  expect(cpuProblem({ ...container, cpuLimit: '0.05' }, offer)).toBe('CPU limit must be between 0.1 and 2 cores, or empty for no limit.')
  expect(cpuProblem({ ...container, cpuLimit: '1' }, cpuOffer(oldHelper))).toBe(OLD_HELPER_LIMIT_NOTE)
  expect(cpuProblem({ ...container, cpuSockets: 9 }, offer)).toBeNull()
})

test('the order carries only what differs from before, and only for its kind', () => {
  expect(cpuFields(vm())).toEqual({})
  expect(cpuFields(vm({ cpuSockets: 1, cpuType: 'host' }))).toEqual({})
  expect(cpuFields(vm({ cpu: 8, cpuSockets: '2', cpuType: 'EPYC-Genoa', cpuFlags: { 'nested-virt': 'off', aes: 'on' } }))).toEqual({ cpu_sockets: 2, cpu_type: 'EPYC-Genoa', cpu_flags: { 'nested-virt': 'off', aes: 'on' } })
  expect(cpuFields(vm({ cpuLimit: '1' }))).toEqual({})
  expect(cpuFields(vm({ kind: 'container', cpuLimit: '1.5', cpuSockets: 2, cpuType: 'EPYC', cpuFlags: { aes: 'on' } }))).toEqual({ cpu_limit_percent: 150 })
  expect(cpuFields(vm({ kind: 'container' }))).toEqual({})
})

test('after another machine is picked only what it offers stays', () => {
  const asked = vm({ cpu: 8, cpuSockets: 2, cpuType: 'EPYC-Genoa', cpuFlags: { aes: 'on' }, cpuLimit: '1' })
  expect(cpuAfterChange(asked, cpuOffer(linux))).toEqual({ cpuSockets: 2, cpuType: 'EPYC-Genoa', cpuFlags: { aes: 'on' }, cpuLimit: '1' })
  expect(cpuAfterChange(asked, cpuOffer(oldHelper))).toEqual({ cpuSockets: undefined, cpuType: undefined, cpuFlags: undefined, cpuLimit: undefined })
  const typesOnly = machine({ capabilities: { ...kinds, cpu_models: ['host', 'Skylake-Server'], cpu_flags: ['aes'] } })
  expect(cpuAfterChange(asked, cpuOffer(typesOnly))).toEqual({ cpuSockets: undefined, cpuType: undefined, cpuFlags: { aes: 'on' }, cpuLimit: undefined })
})

test('a flag reads Default until a button names it, and Default takes it out again', () => {
  expect(flagSetting(vm(), 'aes')).toBe('default')
  const on = withFlag(undefined, 'aes', 'on')
  expect(on).toEqual({ aes: 'on' })
  expect(flagSetting(vm({ cpuFlags: on }), 'aes')).toBe('on')
  expect(withFlag(on, 'nested-virt', 'off')).toEqual({ aes: 'on', 'nested-virt': 'off' })
  expect(withFlag(on, 'aes', 'default')).toBeUndefined()
})

test('Supported on names the machines whose helper can switch the flag', () => {
  const second = machine({ id: 'b', name: 'alpha-box', capabilities: { ...kinds, cpu_flags: ['aes'] } })
  expect(flagMachines([linux, oldHelper, mac, second], 'aes')).toEqual(['alpha-box', 'PC-RTX-5090'])
  expect(flagMachines([linux, oldHelper, mac, second], 'nested-virt')).toEqual(['PC-RTX-5090'])
  expect(flagMachines([oldHelper], 'aes')).toEqual([])
})

test('numbers typed in the boxes pick the preset they match, else Custom', () => {
  expect(matchingSize(2, 4, 40)).toBe('medium')
  expect(matchingSize('1', '2', '20')).toBe('small')
  expect(matchingSize(4, 8, 60)).toBe('large')
  expect(matchingSize(3, 4, 40)).toBe('custom')
  expect(matchingSize('', 4, 40)).toBe('custom')
})
