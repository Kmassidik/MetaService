import { expect, test } from 'bun:test'
import { formFromMachine, type EnvForm } from './environmentForm.ts'
import { limitsSummary, machineSummary, namesSummary, ruvioSummary, softwareSummary, unsavedText, vmDefaultsSummary } from './environmentSummary.ts'
import { machine } from './testing.ts'
import type { Machine } from './types.ts'

const form = (settings: NonNullable<Machine['settings']> = {}, name = 'mac-studio'): EnvForm => formFromMachine(machine({ name, settings }))
const noBadWords = (text: string) => expect(text).not.toMatch(/undefined|null|NaN/)

test('this machine: state, cores, memory and system', () => {
  expect(machineSummary(machine({ state: 'online', cpu_cores: 14, ram_total_mb: 36864 }))).toBe('online · 14 cores · 36 GB · macOS')
})

test('this machine leaves out what is not reported', () => {
  const text = machineSummary(machine({ state: 'offline', os: 'plan9' }))
  expect(text).toBe('offline')
  noBadWords(text)
})

test('software follows the helper status', () => {
  expect(softwareSummary('up_to_date')).toBe('helper up to date')
  expect(softwareSummary('available')).toBe('helper update available')
  expect(softwareSummary('unknown')).toBe('helper version not reported')
  expect(softwareSummary('cannot')).toBe('helper version not reported')
})

test('ruvio is off, on with a version, or on without one', () => {
  expect(ruvioSummary(false, '0.4.0')).toBe('off')
  expect(ruvioSummary(true, '0.4.0')).toBe('on · 0.4.0')
  expect(ruvioSummary(true, null)).toBe('on')
  expect(ruvioSummary(true, undefined)).toBe('on')
})

test('limits with nothing set say so', () => {
  expect(limitsSummary(form())).toBe('no limits set')
})

test('limits name every part that is set, in order', () => {
  const text = limitsSummary(form({ ram_reserve_mb: 2048, disk_reserve_gb: 40, ram_allowance_mb: 4096, disk_allowance_gb: 100, vm_max_running: 4, allow_gpu: true }))
  expect(text).toBe('keeps 2048 MB RAM free · keeps 40 GB disk free · VMs up to 4096 MB RAM · VMs up to 100 GB disk · up to 4 VMs · GPU offered')
})

test('limits say when the GPU is not offered, even with nothing else set', () => {
  expect(limitsSummary(form({ allow_gpu: false }))).toBe('GPU not offered')
  expect(limitsSummary(form({ vm_max_running: 2, allow_gpu: false }))).toBe('up to 2 VMs · GPU not offered')
})

test('limits follow what is typed, unsaved, and ignore blanks', () => {
  const typed = { ...form(), ramReserveMb: '  ', diskReserveGb: '10' }
  expect(limitsSummary(typed)).toBe('keeps 10 GB disk free · GPU offered')
})

test('a new VM gets: the sizes that are set, or the standard ones', () => {
  expect(vmDefaultsSummary(form({ vm_cpu: 4, vm_ram_mb: 4096, vm_disk_gb: 20, vm_image: 'ubuntu-24' }))).toBe('4 CPU · 4096 MB RAM · 20 GB disk · image ubuntu-24')
  expect(vmDefaultsSummary(form({ vm_ram_mb: 2048 }))).toBe('2048 MB RAM')
  expect(vmDefaultsSummary(form())).toBe('uses the standard sizes')
})

test('names: the name, then the parts that are set', () => {
  expect(namesSummary(form({ labels: ['lab', 'gpu'], subdomain: 'studio', ssh_jump: 'me@host:22' }))).toBe('mac-studio · 2 labels · name on the internet studio · ssh me@host:22')
  expect(namesSummary(form({ labels: ['lab'] }))).toBe('mac-studio · 1 label')
  expect(namesSummary(form())).toBe('mac-studio')
})

test('names with an empty name does not print blanks', () => {
  const text = namesSummary({ ...form({ subdomain: 'studio' }), name: '' })
  expect(text).toBe('name on the internet studio')
  noBadWords(text)
  expect(namesSummary({ ...form(), name: '' })).toBe('no name set')
})

test('the save bar counts sections', () => {
  expect(unsavedText(0)).toBe('No unsaved changes')
  expect(unsavedText(1)).toBe('Unsaved changes in 1 section')
  expect(unsavedText(2)).toBe('Unsaved changes in 2 sections')
})
