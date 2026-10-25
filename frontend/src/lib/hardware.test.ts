import { test, expect } from 'bun:test'
import { cpuText, driveSize, drivesText, ghz, gpuDetailText, gpuName, gpuShortText, memorySharedWithGpu, readHardware, USES_MACHINE_MEMORY } from './hardware.ts'
import { machine } from './testing.ts'
import type { Gpu } from './types.ts'

/** What a DGX Spark's helper says (read on the real machine, 25 Oct 2026). */
const SPARK_HARDWARE = {
  system: 'NVIDIA DGX Spark',
  core_types: [{ name: 'Cortex-X925', cores: 10, max_mhz: 3900 }, { name: 'Cortex-A725', cores: 10, max_mhz: 2808 }],
  disks: [{ model: 'SAMSUNG MZALC4T0HBL1-00B07', size_gb: 4097, kind: 'nvme' }],
}
const SPARK_GPU: Gpu = { vendor: 'nvidia', model: 'NVIDIA GB10', architecture: 'Blackwell', compute_capability: '12.1', driver_version: '580.173.02', max_clock_mhz: 3003, uses_system_memory: true }
const RTX_5090: Gpu = { vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090', memory_mb: 32607, architecture: 'Blackwell', compute_capability: '12.0', driver_version: '580.178.04', max_clock_mhz: 3090, uses_system_memory: false }

test('readHardware keeps what is in shape and leaves the rest out', () => {
  expect(readHardware(SPARK_HARDWARE)).toEqual({ system: 'NVIDIA DGX Spark', core_types: SPARK_HARDWARE.core_types, disks: [{ model: 'SAMSUNG MZALC4T0HBL1-00B07', size_gb: 4097, kind: 'nvme' }] })
  const odd = readHardware({ system: '  \u0000 ', core_types: [{ name: 'X', cores: 0 }, { name: 'Y', cores: 4, max_mhz: 999999 }, 'junk'], disks: [{ model: 'Z', size_gb: 10, kind: 'tape' }, { model: 'W', size_gb: 1.5, kind: 'ssd' }] })
  expect(odd).toEqual({ core_types: [{ name: 'Y', cores: 4 }], disks: [] })
  expect(readHardware({ system: `A${'b'.repeat(300)}` })?.system?.length).toBe(120)
  expect(readHardware(null)).toBeNull()
  expect(readHardware(undefined)).toBeNull()
  expect(readHardware([])).toBeNull()
  expect(readHardware({})).toBeNull()
  expect(readHardware({ system: '', core_types: 'no', disks: {} })).toBeNull()
})

test('clocks and drive sizes read the way they are sold', () => {
  expect(ghz(3900)).toBe('3.9 GHz')
  expect(ghz(5086)).toBe('5.1 GHz')
  expect(driveSize(4097)).toBe('4.1 TB')
  expect(driveSize(10001)).toBe('10 TB')
  expect(driveSize(1000)).toBe('1 TB')
  expect(driveSize(512)).toBe('512 GB')
})

test('a chip with two kinds of core names both, with their clocks and the total', () => {
  const spark = machine({ arch: 'aarch64', cpu_cores: 20, cpu_model: 'Cortex-X925 + Cortex-A725', hardware: SPARK_HARDWARE })
  expect(cpuText(spark)).toBe('10× Cortex-X925 up to 3.9 GHz + 10× Cortex-A725 up to 2.8 GHz · 20 cores')
})

test('one kind of core: the name, cores, threads when there are more, and the top clock', () => {
  const ryzen = { core_types: [{ name: 'AMD Ryzen 9 5950X 16-Core Processor', cores: 16, max_mhz: 5086 }] }
  expect(cpuText(machine({ cpu_cores: 32, cpu_model: 'AMD Ryzen 9 5950X 16-Core Processor', hardware: ryzen }))).toBe('AMD Ryzen 9 5950X 16-Core Processor · 16 cores, 32 threads · up to 5.1 GHz')
  expect(cpuText(machine({ cpu_cores: 4, cpu_model: null, hardware: { core_types: [{ name: 'Cortex-A72', cores: 4 }] } }))).toBe('Cortex-A72 · 4 cores')
  expect(cpuText(machine({ cpu_cores: 1, hardware: { core_types: [{ name: 'Tiny', cores: 1 }] } }))).toBe('Tiny · 1 core')
})

test('without core types the CPU row is what it was', () => {
  expect(cpuText(machine({ cpu_cores: 16, cpu_model: 'AMD EPYC 7763 64-Core Processor' }))).toBe('AMD EPYC 7763 64-Core Processor · 16 cores')
  expect(cpuText(machine({ cpu_cores: 16 }))).toBe('16 cores')
  expect(cpuText(machine({}))).toBe('– cores')
})

test('drives read biggest first as the helper sends them, each with its size and kind', () => {
  expect(drivesText(readHardware(SPARK_HARDWARE))).toBe('SAMSUNG MZALC4T0HBL1-00B07 · 4.1 TB NVMe')
  const pc = readHardware({ disks: [{ model: 'ST10000NE0004-2G', size_gb: 10001, kind: 'hdd' }, { model: 'Corsair MP700 ELITE', size_gb: 1000, kind: 'nvme' }] })
  expect(drivesText(pc)).toBe('ST10000NE0004-2G · 10 TB HDD, Corsair MP700 ELITE · 1 TB NVMe')
  expect(drivesText(readHardware({ system: 'X' }))).toBeNull()
  expect(drivesText(null)).toBeNull()
})

test('a GPU is named once, with its family, memory, capability, clock and driver', () => {
  expect(gpuName(SPARK_GPU)).toBe('NVIDIA GB10')
  expect(gpuName({ vendor: 'nvidia', model: 'GB10' })).toBe('nvidia GB10')
  expect(gpuShortText(SPARK_GPU)).toBe(`NVIDIA GB10 · Blackwell · ${USES_MACHINE_MEMORY}`)
  expect(gpuDetailText(SPARK_GPU)).toBe(`NVIDIA GB10 · Blackwell · ${USES_MACHINE_MEMORY} · compute 12.1 · up to 3,003 MHz · driver 580.173.02`)
  expect(gpuDetailText(RTX_5090)).toBe('NVIDIA GeForce RTX 5090 · Blackwell · 31.8 GB · compute 12.0 · up to 3,090 MHz · driver 580.178.04')
  expect(gpuDetailText({ vendor: 'nvidia', model: 'NVIDIA T4', memory_mb: 15360 })).toBe('NVIDIA T4 · 15 GB')
  expect(gpuDetailText({ vendor: 'nvidia', model: 'NVIDIA X', max_clock_mhz: 0, compute_capability: '\u0000', driver_version: null })).toBe('NVIDIA X')
})

test('the memory is shared with the GPU exactly when a GPU says it uses it', () => {
  expect(memorySharedWithGpu(machine({ gpu: [SPARK_GPU] }))).toBe(true)
  expect(memorySharedWithGpu(machine({ gpu: [RTX_5090] }))).toBe(false)
  expect(memorySharedWithGpu(machine({ gpu: [] }))).toBe(false)
})
