import { expect, test } from 'bun:test'
import { initialSize, presetCaption, sizeCards, sizeProblem, SIZE_PRESETS } from './vmSize.ts'
import { machine } from './testing.ts'

const roomy = machine({ cpu_cores: 8, free_ram_mb: 16384, free_disk_gb: 500 })

test('the three presets are Small, Medium and Large with their captions', () => {
  expect(SIZE_PRESETS.map((preset) => `${preset.label}: ${presetCaption(preset)}`)).toEqual(['Small: 1 · 2GB · 20GB', 'Medium: 2 · 4GB · 40GB', 'Large: 4 · 8GB · 60GB'])
})

test('on a roomy machine all four cards can be picked and Custom comes last', () => {
  const cards = sizeCards(roomy)
  expect(cards.map((card) => card.key)).toEqual(['small', 'medium', 'large', 'custom'])
  expect(cards.every((card) => !card.disabled && card.reason === null)).toBe(true)
  expect(cards[3]).toMatchObject({ label: 'Custom', caption: 'your specs' })
})

test('a preset that needs more RAM than is free is greyed out and says how much is free', () => {
  const cards = sizeCards(machine({ cpu_cores: 8, free_ram_mb: 6144, free_disk_gb: 500 }))
  expect(cards.map((card) => card.disabled)).toEqual([false, false, true, false])
  expect(cards[2]?.reason).toBe('This machine has 6 GB free')
})

test('disk and CPU limits are explained too, RAM first', () => {
  expect(sizeProblem(SIZE_PRESETS[1]!, machine({ free_disk_gb: 30 }))).toBe('This machine has 30 GB disk free')
  expect(sizeProblem(SIZE_PRESETS[2]!, machine({ cpu_cores: 2 }))).toBe('This machine has 2 CPUs')
  expect(sizeProblem(SIZE_PRESETS[0]!, machine({ cpu_cores: 0 }))).toBe('This machine has 0 CPUs')
  expect(sizeProblem(SIZE_PRESETS[2]!, machine({ cpu_cores: 2, free_ram_mb: 1024 }))).toBe('This machine has 2 CPUs')
})

test('a size that exactly uses what is free fits', () => {
  expect(sizeProblem(SIZE_PRESETS[1]!, machine({ cpu_cores: 2, free_ram_mb: 4096, free_disk_gb: 40 }))).toBeNull()
})

test('a machine that has not reported its space greys out nothing; the machine decides', () => {
  expect(sizeProblem(SIZE_PRESETS[2]!, machine())).toBeNull()
  expect(sizeProblem(SIZE_PRESETS[2]!, undefined)).toBeNull()
})

test('without defaults the window starts on Medium', () => {
  expect(initialSize(roomy, {})).toEqual({ key: 'medium', cpu: 2, ramGb: 4, diskGb: 40 })
})

test('without defaults on a small machine it starts on the first preset that fits, or on Custom when none does', () => {
  expect(initialSize(machine({ free_ram_mb: 2048 }), {}).key).toBe('small')
  expect(initialSize(machine({ free_ram_mb: 512 }), {})).toEqual({ key: 'custom', cpu: 2, ramGb: 4, diskGb: 40 })
})

test('defaults that equal a preset select that preset', () => {
  expect(initialSize(roomy, { cpu: 1, ramGb: 2, diskGb: 20 }).key).toBe('small')
  expect(initialSize(roomy, { cpu: 4, ramGb: 8, diskGb: 60 }).key).toBe('large')
})

test('other defaults select Custom filled with them, and missing parts come from Medium', () => {
  expect(initialSize(roomy, { cpu: 3, ramGb: 6, diskGb: 50 })).toEqual({ key: 'custom', cpu: 3, ramGb: 6, diskGb: 50 })
  expect(initialSize(roomy, { cpu: 6 })).toEqual({ key: 'custom', cpu: 6, ramGb: 4, diskGb: 40 })
})
