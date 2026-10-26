import { test, expect } from 'bun:test'
import { addressLine, chipName, hardwareLine, hardwareParts, NO_VMS, UNKNOWN, vmsChip } from './cardFacts.ts'
import { machine } from './testing.ts'

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

test('the one hardware line reads the system, the chip, the cores and the machine name', () => {
  expect(hardwareLine(MAC)).toBe('macOS · Apple Silicon · 14 cores · Apple M4 Max')
  expect(hardwareLine(SPARK)).toBe('Linux · ARM · 20 cores · NVIDIA GB10')
  expect(hardwareLine(PC)).toBe('Linux · x86 · 32 cores · NVIDIA GeForce RTX 5090')
})

test('the board and the CPU name share the one line, never two rows', () => {
  const withBoard = machine({ os: 'linux', arch: 'aarch64', cpu_cores: 6, cpu_model: 'Cortex-A76', hardware: { system: 'Radxa Rock 5B', core_types: [], disks: [] } })
  const line = hardwareLine(withBoard)
  expect(line).toBe('Linux · ARM · 6 cores · Cortex-A76')
  expect(line.split(' · ')).toHaveLength(4)
  expect(hardwareParts(withBoard).map((part) => part.kind)).toEqual(['os', 'chip', 'cores', 'cpu'])
})

test('a machine with no GPU or CPU name falls back to the computer model, then to the dash', () => {
  const boardOnly = machine({ os: 'macos', arch: 'arm64', cpu_cores: 8, hardware: { system: 'Mac mini (2024)', core_types: [], disks: [] } })
  expect(hardwareLine(boardOnly)).toBe('macOS · Apple Silicon · 8 cores · Mac mini (2024)')
  expect(hardwareLine(machine({ os: 'macos', arch: 'arm64', cpu_cores: 8 }))).toBe('macOS · Apple Silicon · 8 cores · —')
})

test('every missing piece keeps its place as a dash, so the line is always one line', () => {
  expect(hardwareLine(machine({ os: 'linux', arch: 'x86_64', cpu_cores: 4 }))).toBe('Linux · x86 · 4 cores · —')
  expect(hardwareLine(machine({ os: 'linux', arch: '', cpu_cores: 4 }))).toBe('Linux · — · 4 cores · —')
  expect(hardwareLine(machine({ os: '', arch: '', cpu_cores: 4 }))).toBe('— · — · 4 cores · —')
  expect(hardwareLine(machine({ os: 'linux', arch: 'x86_64', cpu_cores: 1 }))).toBe('Linux · x86 · 1 core · —')
  expect(hardwareLine(machine({ os: 'linux', arch: 'x86_64', cpu_cores: null }))).toBe('Linux · x86 · — · —')
  expect(hardwareLine(machine({ os: 'linux', arch: 'x86_64', cpu_cores: 0 }))).toBe('Linux · x86 · — · —')
})

test('a machine that says nothing about itself gets the one dash', () => {
  expect(hardwareLine(machine({ os: 'plan9', arch: 'z80' }))).toBe(UNKNOWN)
  expect(hardwareLine(machine({ os: '', arch: '' }))).toBe(UNKNOWN)
})

test('the chip is "Apple Silicon" only for a Mac on Apple chips', () => {
  expect(chipName(machine({ os: 'macos', arch: 'arm64' }))).toBe('Apple Silicon')
  expect(chipName(machine({ os: 'macos', arch: 'x86_64' }))).toBe('x86')
  expect(chipName(machine({ os: 'linux', arch: 'aarch64' }))).toBe('ARM')
  expect(chipName(machine({ os: 'linux', arch: '' }))).toBe(UNKNOWN)
})

test('a card with no hardware data still fills every row', () => {
  const bare = machine({ os: '', arch: '' })
  expect(hardwareLine(bare)).toBe(UNKNOWN)
  expect(addressLine(bare)).toBe('— · Other')
  expect(vmsChip(bare.workloads.length)).toBe(NO_VMS)
})

test('the address line is the address and the profile, one line', () => {
  expect(addressLine(machine({ ip: '192.168.0.40', settings: { profile: 'gpu-box' } }))).toBe('192.168.0.40 · GPU box (DGX)')
  expect(addressLine(machine({ ip: '192.168.0.40' }))).toBe('192.168.0.40 · Other')
  expect(addressLine(machine({}))).toBe('— · Other')
})

test('the header chip says how many VMs, and "No VMs" when there are none', () => {
  expect(vmsChip(0)).toBe(NO_VMS)
  expect(vmsChip(1)).toBe('1 VM')
  expect(vmsChip(2)).toBe('2 VMs')
  expect(vmsChip(7)).toBe('7 VMs')
})
