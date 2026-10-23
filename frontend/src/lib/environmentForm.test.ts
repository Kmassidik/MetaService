import { test, expect } from 'bun:test'
import { MAX_LABELS, MAX_NOTES, NUMBER_RULES, formErrors, formFromMachine, labelsProblem, notesProblem, numberProblem, parseLabels, patchFor, readNumber, sameForm, textProblem, type EnvForm, type NumberField } from './environmentForm.ts'
import { machine } from './testing.ts'
import type { Machine } from './types.ts'

/** The real mac-studio record: macos arm64, 14 cores, 36864 MB, 494 GB, engine apple, no chat, no VMs, default settings. */
const studio = (): Machine => machine({
  id: 'mac-studio', name: 'mac-studio', cpu_cores: 14, ram_total_mb: 36864, disk_total_gb: 494, engine: { name: 'apple', version: '1.5.0', ready: true },
  settings: { profile: 'custom', labels: [], notes: '', allow_gpu: true },
})
const form = (extra: Partial<EnvForm> = {}): EnvForm => ({ ...formFromMachine(studio()), ...extra })

test('formFromMachine of the default record is empty apart from the name and the GPU offer', () => {
  expect(formFromMachine(studio())).toEqual({
    name: 'mac-studio', labels: '', notes: '', allowGpu: true, ramReserveMb: '', diskReserveGb: '', ramAllowanceMb: '', diskAllowanceGb: '', vmMaxRunning: '',
    vmCpu: '', vmRamMb: '', vmDiskGb: '', vmImage: '', subdomain: '', aiModel: '', sshJump: '',
  })
})

test('formFromMachine reads every saved setting, and a machine with no settings gets the defaults', () => {
  const saved = machine({ name: 'dgx', settings: { labels: ['gpu', 'lab'], notes: 'rack 2', allow_gpu: false, ram_reserve_mb: 2048, vm_cpu: 4, vm_image: 'ubuntu:24.04', subdomain: 'dgx', ai_model: 'm1', ssh_jump: 'me@dgx.example.com:22' } })
  expect(formFromMachine(saved)).toMatchObject({ labels: 'gpu, lab', notes: 'rack 2', allowGpu: false, ramReserveMb: '2048', vmCpu: '4', vmImage: 'ubuntu:24.04', subdomain: 'dgx', aiModel: 'm1', sshJump: 'me@dgx.example.com:22' })
  expect(formFromMachine(machine({ name: 'x' }))).toMatchObject({ allowGpu: true, notes: '', labels: '' })
})

test('sameForm tells a change from none', () => {
  expect(sameForm(form(), form())).toBe(true)
  expect(sameForm(form(), form({ notes: 'a' }))).toBe(false)
  expect(sameForm(form(), form({ allowGpu: false }))).toBe(false)
})

test('parseLabels splits on commas and spaces and drops empties', () => {
  expect(parseLabels('a, b  c,,d')).toEqual(['a', 'b', 'c', 'd'])
  expect(parseLabels('')).toEqual([])
  expect(parseLabels(' , ')).toEqual([])
})

test('readNumber: empty is null, otherwise the number', () => {
  expect(readNumber('')).toBeNull()
  expect(readNumber('  ')).toBeNull()
  expect(readNumber('16')).toBe(16)
  expect(readNumber('0')).toBe(0)
})

test('the ranges are the parent\'s (MachineSettings.swift)', () => {
  expect(NUMBER_RULES).toEqual({
    ramReserveMb: { label: 'Memory kept free (MB)', min: 0, max: 10_000_000 },
    diskReserveGb: { label: 'Disk kept free (GB)', min: 0, max: 10_000_000 },
    ramAllowanceMb: { label: 'Most memory VMs may use (MB)', min: 512, max: 10_000_000 },
    diskAllowanceGb: { label: 'Most disk VMs may use (GB)', min: 1, max: 10_000_000 },
    vmMaxRunning: { label: 'Most VMs at once', min: 1, max: 1000 },
    vmCpu: { label: 'CPU', min: 1, max: 64 },
    vmRamMb: { label: 'Memory (MB)', min: 512, max: 1_048_576 },
    vmDiskGb: { label: 'Disk (GB)', min: 1, max: 100_000 },
  })
})

test('numberProblem accepts empty and the edges of every range, and refuses one step outside', () => {
  const fields: NumberField[] = ['ramReserveMb', 'diskReserveGb', 'ramAllowanceMb', 'diskAllowanceGb', 'vmMaxRunning', 'vmCpu', 'vmRamMb', 'vmDiskGb']
  for (const field of fields) {
    const { min, max } = NUMBER_RULES[field]
    expect(numberProblem(field, '')).toBeNull()
    expect(numberProblem(field, String(min))).toBeNull()
    expect(numberProblem(field, String(max))).toBeNull()
    expect(numberProblem(field, String(max + 1))).toContain(`between ${min} and ${max}`)
    if (min > 0) expect(numberProblem(field, String(min - 1))).toContain(`between ${min} and ${max}`)
  }
})

test('numberProblem refuses anything that is not a whole number', () => {
  for (const bad of ['1.5', '-1', '1e3', 'abc', '0x10', '1 2', '+5', '٣']) expect(numberProblem('vmCpu', bad)).toContain('whole number')
})

test('textProblem follows the parent\'s patterns', () => {
  expect(textProblem('vmImage', '')).toBeNull()
  expect(textProblem('vmImage', 'ubuntu:24.04')).toBeNull()
  expect(textProblem('vmImage', 'ubuntu 24')).toContain('Image')
  expect(textProblem('vmImage', 'Ubuntu')).toContain('use lowercase')
  expect(textProblem('vmImage', 'a'.repeat(129))).toContain('at most 128')
  expect(textProblem('subdomain', 'mac-studio')).toBeNull()
  expect(textProblem('subdomain', '-mac')).not.toBeNull()
  expect(textProblem('subdomain', 'mac.studio')).not.toBeNull()
  expect(textProblem('subdomain', 'a'.repeat(32))).toContain('at most 31')
  expect(textProblem('aiModel', 'Grok-4.1:fast/x')).toBeNull()
  expect(textProblem('aiModel', '_x')).not.toBeNull()
  expect(textProblem('aiModel', 'a b')).not.toBeNull()
  expect(textProblem('aiModel', 'a'.repeat(101))).toContain('at most 100')
})

test('labelsProblem: count, shape and duplicates', () => {
  expect(labelsProblem('')).toBeNull()
  expect(labelsProblem('gpu, lab')).toBeNull()
  expect(labelsProblem(Array.from({ length: MAX_LABELS }, (_, i) => `l${i}`).join(' '))).toBeNull()
  expect(labelsProblem(Array.from({ length: MAX_LABELS + 1 }, (_, i) => `l${i}`).join(' '))).toContain('at most 8')
  expect(labelsProblem('a, a')).toContain('different')
  expect(labelsProblem('Big')).toContain('"Big"')
  expect(labelsProblem('-x')).not.toBeNull()
  expect(labelsProblem('a'.repeat(31))).not.toBeNull()
})

test('notesProblem allows the limit and refuses one more', () => {
  expect(notesProblem('x'.repeat(MAX_NOTES))).toBeNull()
  expect(notesProblem('x'.repeat(MAX_NOTES + 1))).toContain('300')
})

test('formErrors of the default record is empty', () => {
  expect(formErrors(form())).toEqual({})
})

test('formErrors names the name field with the machine-name rule', () => {
  expect(formErrors(form({ name: '' })).name).toBe('Give the machine a name.')
  expect(formErrors(form({ name: 'Big Name' })).name).toBeUndefined()
  expect(formErrors(form({ name: 'Luca\'s PC (RTX)' })).name).toBeUndefined()
  expect(formErrors(form({ name: 'a;b' })).name).toContain('up to 48 characters')
  expect(formErrors(form({ name: 'a'.repeat(49) })).name).toContain('up to 48 characters')
})

test('formErrors refuses a reserve that is not below the allowance, like the parent', () => {
  expect(formErrors(form({ ramReserveMb: '4096', ramAllowanceMb: '4096' })).ramReserveMb).toContain('memory kept free must be smaller')
  expect(formErrors(form({ diskReserveGb: '300', diskAllowanceGb: '200' })).diskReserveGb).toContain('disk kept free must be smaller')
  expect(formErrors(form({ ramReserveMb: '1024', ramAllowanceMb: '4096' }))).toEqual({})
  expect(formErrors(form({ ramReserveMb: '1024' }))).toEqual({})
})

test('formErrors reports a bad number once, not also as a clash', () => {
  const errors = formErrors(form({ ramReserveMb: 'x', ramAllowanceMb: '600' }))
  expect(errors.ramReserveMb).toContain('whole number')
})

test('formErrors collects every bad field at once', () => {
  const errors = formErrors(form({ vmCpu: '65', vmImage: 'Bad Image', subdomain: '-', aiModel: '', labels: 'a,a', notes: 'x'.repeat(301) }))
  expect(Object.keys(errors).sort()).toEqual(['labels', 'notes', 'subdomain', 'vmCpu', 'vmImage'])
})

test('hostile text is refused by every text field and cannot reach the parent', () => {
  const hostile = ['<script>alert(1)</script>', "'; DROP TABLE machines;--", '../../etc/passwd', 'a\u0000b', '${jndi:ldap://x}', '"; rm -rf /']
  for (const value of hostile) {
    const errors = formErrors(form({ name: value, labels: value, vmImage: value, subdomain: value, aiModel: value }))
    expect(Object.keys(errors).sort()).toEqual(['aiModel', 'labels', 'name', 'subdomain', 'vmImage'])
  }
})

test('hostile text in the notes is accepted as text only up to the limit (the page shows it as text, the parent stores it as text)', () => {
  expect(notesProblem('<img src=x onerror=alert(1)>')).toBeNull()
})

test('patchFor sends nothing when nothing changed', () => {
  expect(patchFor(form(), studio())).toEqual({})
})

test('patchFor sends only the fields that changed', () => {
  expect(patchFor(form({ name: 'studio-2', vmCpu: '4', allowGpu: false }), studio())).toEqual({ name: 'studio-2', vm_cpu: 4, allow_gpu: false })
})

test('patchFor sends every field it knows with the parent\'s names', () => {
  const everything = form({
    name: 'n', labels: 'a, b', notes: 'hello', allowGpu: false, ramReserveMb: '1024', diskReserveGb: '10', ramAllowanceMb: '8192', diskAllowanceGb: '200', vmMaxRunning: '3',
    vmCpu: '2', vmRamMb: '2048', vmDiskGb: '20', vmImage: 'ubuntu:24.04', subdomain: 'sub', aiModel: 'model-1', sshJump: 'you@studio.example.com:2222',
  })
  expect(patchFor(everything, studio())).toEqual({
    name: 'n', labels: ['a', 'b'], notes: 'hello', allow_gpu: false, ram_reserve_mb: 1024, disk_reserve_gb: 10, ram_allowance_mb: 8192, disk_allowance_gb: 200, vm_max_running: 3,
    vm_cpu: 2, vm_ram_mb: 2048, vm_disk_gb: 20, vm_image: 'ubuntu:24.04', subdomain: 'sub', ai_model: 'model-1', ssh_jump: 'you@studio.example.com:2222',
  })
})

test('patchFor clears an emptied field with null, but never clears name, labels, notes or the GPU offer', () => {
  const had = machine({ name: 'a', settings: { vm_cpu: 4, vm_image: 'x', subdomain: 's', ai_model: 'm', ssh_jump: 'a@b', ram_reserve_mb: 5, labels: ['l'], notes: 'n' } })
  const cleared = patchFor({ ...formFromMachine(had), vmCpu: '', vmImage: '', subdomain: '', aiModel: '', sshJump: '', ramReserveMb: '', labels: '', notes: '' }, had)
  expect(cleared).toEqual({ vm_cpu: null, vm_image: null, subdomain: null, ai_model: null, ssh_jump: null, ram_reserve_mb: null, labels: [], notes: '' })
})

test('patchFor treats 0 as a value, not as empty', () => {
  expect(patchFor(form({ ramReserveMb: '0' }), studio())).toEqual({ ram_reserve_mb: 0 })
})

test('patchFor does not resend an unchanged value that the parent already has', () => {
  const had = machine({ name: 'a', settings: { vm_cpu: 4, labels: ['x', 'y'] } })
  expect(patchFor({ ...formFromMachine(had), notes: '' }, had)).toEqual({})
  expect(patchFor({ ...formFromMachine(had), labels: 'x y' }, had)).toEqual({})
  expect(patchFor({ ...formFromMachine(had), labels: 'y, x' }, had)).toEqual({ labels: ['y', 'x'] })
})

test('the SSH address takes user@host and user@host:port, and refuses the rest in plain words', () => {
  const refusal = 'Use the form user@host or user@host:port.'
  for (const good of ['you@203.0.113.7', 'you@studio.example.com:2222', 'a.b_c-d@host-1.example.org']) expect(textProblem('sshJump', good)).toBeNull()
  for (const bad of ['studio.example.com', 'you@', '@host', 'you@host:', 'you@host:123456', 'you@ho st', 'ssh you@host', 'you@host:22/x']) expect(textProblem('sshJump', bad)).toBe(refusal)
  expect(textProblem('sshJump', '')).toBeNull()
  expect(textProblem('sshJump', `${'a'.repeat(119)}@h`)).toContain('at most 120')
})

test('an emptied SSH address is sent as null, a changed one as ssh_jump, an unchanged one not at all', () => {
  const had = machine({ name: 'a', settings: { ssh_jump: 'you@host' } })
  expect(patchFor({ ...formFromMachine(had), sshJump: '' }, had)).toEqual({ ssh_jump: null })
  expect(patchFor({ ...formFromMachine(had), sshJump: 'me@other:2200' }, had)).toEqual({ ssh_jump: 'me@other:2200' })
  expect(patchFor(formFromMachine(had), had)).toEqual({})
})
