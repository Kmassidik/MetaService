import { expect, test } from 'bun:test'
import { badgeFace, runtimeCaption, runtimeOptions, sizeOptions } from './createSelects.ts'
import { machineChoices, runtimeCards } from './createVm.ts'
import { sizeCards } from './vmSize.ts'
import { machine } from './testing.ts'

const caps = (vm: boolean, container: boolean) => ({ vm, container, gpu_in_vm: false, gpu_in_container: false })

test('the size select lists the three presets and Custom, Medium marked Recommended', () => {
  const lines = sizeOptions(sizeCards(machine({ cpu_cores: 8, free_ram_mb: 16384, free_disk_gb: 500 })))
  expect(lines.map((line) => line.label)).toEqual([
    'Small — 1 vCPU · 2GB RAM · 20GB Disk',
    'Medium — 2 vCPU · 4GB RAM · 40GB Disk (Recommended)',
    'Large — 4 vCPU · 8GB RAM · 60GB Disk',
    'Custom — Configure specs manually...',
  ])
  expect(lines.every((line) => !line.disabled)).toBe(true)
})

test('a size the machine cannot hold is disabled with the reason in brackets', () => {
  const lines = sizeOptions(sizeCards(machine({ cpu_cores: 8, free_ram_mb: 6144, free_disk_gb: 500 })))
  expect(lines[2]).toEqual({ value: 'large', label: 'Large — 4 vCPU · 8GB RAM · 60GB Disk (This machine has 6 GB free)', disabled: true })
  expect(lines[3]?.disabled).toBe(false)
})

test('the runtime select names both kinds, and the one the machine cannot run says why in brackets', () => {
  const both = machineChoices([machine({ id: 'a', name: 'a', capabilities: caps(true, true) })])[0]
  expect(runtimeOptions(runtimeCards(both)).map((line) => line.label)).toEqual(['Container — fast stop & wake', 'VM — full VM, classic'])
  const only = machineChoices([machine({ id: 'b', name: 'b', capabilities: caps(false, true) })])[0]
  expect(runtimeOptions(runtimeCards(only))[1]).toEqual({ value: 'vm', label: 'VM — full VM, classic (this machine runs containers only)', disabled: true })
})

test("the line under the runtime select follows the choice, and a Mac adds that both run in Apple's small VM", () => {
  expect(runtimeCaption('container', 'linux')).toBe("Shares the machine's core: starts in seconds, uses little memory.")
  expect(runtimeCaption('vm', 'linux')).toBe('A whole separate computer with its own core: stronger wall, slower start.')
  expect(runtimeCaption('container', 'macos')).toBe("Shares the machine's core: starts in seconds, uses little memory. On a Mac both run inside Apple's own small VM.")
})

test('an image square shows its logo when it has one, else the first letter', () => {
  expect(badgeFace('openclaw', '/logos/openclaw.svg')).toEqual({ kind: 'logo', src: '/logos/openclaw.svg' })
  expect(badgeFace('openclaw', undefined)).toEqual({ kind: 'letter', text: 'O' })
  expect(badgeFace('Blank (plain Ubuntu)', undefined)).toEqual({ kind: 'letter', text: 'B' })
})
