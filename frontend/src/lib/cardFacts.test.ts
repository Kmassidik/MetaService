import { test, expect } from 'bun:test'
import { cardFacts, chipName, NO_VMS, UNKNOWN, vmsChip } from './cardFacts.ts'
import { machine, workload } from './testing.ts'
import type { FactKey } from './cardFacts.ts'
import type { Machine } from './types.ts'

/** The real DGX Spark, as its helper reports it: the board, both kinds of core, and a GPU that works in the machine's memory. */
const SPARK = machine({
  id: 'dgx-spark', os: 'linux', arch: 'aarch64', cpu_cores: 20, cpu_model: 'Cortex-X925 + Cortex-A725', ip: '192.168.0.40',
  gpu: [{ vendor: 'nvidia', model: 'NVIDIA GB10', uses_system_memory: true }],
  hardware: { system: 'NVIDIA DGX Spark', core_types: [{ name: 'Cortex-X925', cores: 10 }, { name: 'Cortex-A725', cores: 10 }], disks: [] },
})

/** A Mac the way a helper that does not say much reports it: no board, no GPU, the CPU by name. */
const MAC = machine({ id: 'mac-mini', os: 'macos', arch: 'arm64', cpu_cores: 14, cpu_model: 'Apple M4 Max', ip: '192.168.0.41' })

/** A PC chosen for its card. */
const PC = machine({ id: 'pc', os: 'linux', arch: 'x86_64', cpu_cores: 32, ip: '192.168.0.42', gpu: [{ vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090', memory_mb: 32607 }] })

/** The facts as the card draws them, one "LABEL value" string per row. */
const rows = (m: Machine) => cardFacts(m).map((fact) => `${fact.label} ${fact.value}`)

/** The one row of a fact, which every card always has. */
const factOf = (m: Machine, key: FactKey): string | undefined => cardFacts(m).find((fact) => fact.key === key)?.value

test('a full machine gets a row per fact, in the one order every card uses', () => {
  expect(rows(PC)).toEqual([
    'ADDRESS 192.168.0.42',
    'TYPE Other',
    'OS Linux · x86',
    'CORES 32',
    'CPU —',
    'GPU NVIDIA GeForce RTX 5090',
    'VMS No VMs',
  ])
  expect(cardFacts(PC).map((fact) => fact.key)).toEqual(['address', 'type', 'os', 'cores', 'cpu', 'gpu', 'vms'])
})

test('the OS row carries the system and the chip, and the CPU keeps its own row', () => {
  expect(rows(MAC)).toEqual([
    'ADDRESS 192.168.0.41',
    'TYPE Other',
    'OS macOS · Apple Silicon',
    'CORES 14',
    'CPU Apple M4 Max',
    'GPU —',
    'VMS No VMs',
  ])
  expect(rows(SPARK)).toEqual([
    'ADDRESS 192.168.0.40',
    'TYPE Other',
    'OS Linux · ARM',
    'CORES 20',
    'CPU Cortex-X925 + Cortex-A725',
    'GPU NVIDIA GB10',
    'VMS No VMs',
  ])
})

test('a machine with no hardware still fills every row, with a dash', () => {
  const bare = machine({ os: '', arch: '', ip: '' })
  expect(rows(bare)).toEqual(['ADDRESS —', 'TYPE Other', 'OS —', 'CORES —', 'CPU —', 'GPU —', 'VMS No VMs'])
})

test('the OS row keeps the half it knows, and the dash when it knows neither', () => {
  expect(factOf(machine({ os: 'linux', arch: '' }), 'os')).toBe('Linux')
  expect(factOf(machine({ os: '', arch: '' }), 'os')).toBe(UNKNOWN)
  expect(factOf(machine({ os: 'plan9', arch: 'z80' }), 'os')).toBe(UNKNOWN)
})

test('the chip is "Apple Silicon" only for a Mac on Apple chips', () => {
  expect(chipName(machine({ os: 'macos', arch: 'arm64' }))).toBe('Apple Silicon')
  expect(chipName(machine({ os: 'macos', arch: 'x86_64' }))).toBe('x86')
  expect(chipName(machine({ os: 'linux', arch: 'aarch64' }))).toBe('ARM')
  expect(chipName(machine({ os: 'linux', arch: '' }))).toBe(UNKNOWN)
})

test('the GPU row names the card, every card of a machine with more than one, or the dash', () => {
  expect(factOf(PC, 'gpu')).toBe('NVIDIA GeForce RTX 5090')
  expect(factOf(MAC, 'gpu')).toBe(UNKNOWN)
  expect(factOf(machine({ gpu: [{ vendor: 'nvidia', model: 'NVIDIA L4' }, { vendor: 'nvidia', model: 'NVIDIA L4' }] }), 'gpu')).toBe('NVIDIA L4, NVIDIA L4')
})

test('the TYPE row is the profile the person saved, and "Other" when there is none', () => {
  expect(factOf(machine({ settings: { profile: 'gpu-box' } }), 'type')).toBe('GPU box (DGX)')
  expect(factOf(machine({}), 'type')).toBe('Other')
})

test('the VMS row says how many, and "No VMs" when there are none', () => {
  expect(factOf(machine({ workloads: [] }), 'vms')).toBe(NO_VMS)
  expect(factOf(machine({ workloads: [workload()] }), 'vms')).toBe('1 VM')
  expect(factOf(machine({ workloads: [workload(), workload({ id: 'w2' }), workload({ id: 'w3' })] }), 'vms')).toBe('3 VMs')
  expect(vmsChip(0)).toBe(NO_VMS)
  expect(vmsChip(1)).toBe('1 VM')
  expect(vmsChip(2)).toBe('2 VMs')
  expect(vmsChip(7)).toBe('7 VMs')
})

test('a core count that is not a whole number of cores is the dash, and one core is "1"', () => {
  expect(factOf(machine({ cpu_cores: 1 }), 'cores')).toBe('1')
  expect(factOf(machine({ cpu_cores: 0 }), 'cores')).toBe(UNKNOWN)
  expect(factOf(machine({ cpu_cores: null }), 'cores')).toBe(UNKNOWN)
})
