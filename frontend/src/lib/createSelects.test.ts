import { expect, test } from 'bun:test'
import { badgeFace, runtimeCaption, runtimeRows, sizeOptions } from './createSelects.ts'
import { CONTAINER_DESCRIPTION as CONTAINER_TEXT, VM_DESCRIPTION, machineChoices, runtimeCards } from './createVm.ts'
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

test('the runtime dropdown describes both kinds, Container recommended', () => {
  const both = machineChoices([machine({ id: 'a', name: 'a', capabilities: caps(true, true) })])[0]
  const rows = runtimeRows(runtimeCards(both))
  expect(rows.map((row) => [row.id, row.title, row.tag, row.disabled, row.glyph])).toEqual([['container', 'Container', 'Recommended', false, 'container'], ['vm', 'VM', null, false, 'vm']])
  expect(rows[0]?.caption).toBe("Fast stop and wake. Shares the machine's core, so it starts in seconds and uses little memory. Best for agents and apps.")
  expect(rows[1]?.caption).toBe('A full computer with its own core: a stronger wall, slower start, more memory. Needs virtualization on the machine.')
})

test('the kind the machine cannot run is greyed out and gives its reason as the caption', () => {
  const only = machineChoices([machine({ id: 'b', name: 'b', capabilities: caps(false, true) })])[0]
  expect(runtimeRows(runtimeCards(only))[1]).toEqual({ id: 'vm', title: 'VM', caption: 'This machine runs containers only', disabled: true, tag: null, glyph: 'vm' })
})

test("the line under the runtime select follows the choice, and a Mac adds that both run in Apple's small VM", () => {
  expect(runtimeCaption('container', 'linux')).toBe(CONTAINER_TEXT)
  expect(runtimeCaption('vm', 'linux')).toBe(VM_DESCRIPTION)
  expect(runtimeCaption('container', 'macos')).toBe(`${CONTAINER_TEXT} On a Mac both run inside Apple's own small VM.`)
})

test('an image square shows its logo when it has one, else the first letter', () => {
  expect(badgeFace('openclaw', '/logos/openclaw.svg')).toEqual({ kind: 'logo', src: '/logos/openclaw.svg' })
  expect(badgeFace('openclaw', undefined)).toEqual({ kind: 'letter', text: 'O' })
  expect(badgeFace('Alpha', undefined)).toEqual({ kind: 'letter', text: 'A' })
})
