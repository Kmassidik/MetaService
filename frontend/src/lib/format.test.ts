import { test, expect } from 'bun:test'
import { relativeTime, formatMb, formatGb, osName, archName, usedPercent, nameProblem, machineNameProblem, sourceProblem, sourceName, workloadProblem, workloadBody, commandOutcome, commandName, bundleFlag } from './format.ts'
import { command } from './testing.ts'

const now = Date.parse('2026-10-09T12:00:00Z')
const ago = (ms: number) => new Date(now - ms).toISOString()

test('relativeTime', () => {
  expect(relativeTime(null, now)).toBe('never')
  expect(relativeTime('nonsense', now)).toBe('unknown')
  expect(relativeTime(ago(1000), now)).toBe('just now')
  expect(relativeTime(ago(12_000), now)).toBe('12s ago')
  expect(relativeTime(ago(5 * 60_000), now)).toBe('5m ago')
  expect(relativeTime(ago(3 * 3_600_000), now)).toBe('3h ago')
  expect(relativeTime(ago(2 * 86_400_000), now)).toBe('2d ago')
  expect(relativeTime(new Date(now + 60_000).toISOString(), now)).toBe('just now')
})

test('sizes', () => {
  expect(formatMb(512)).toBe('512 MB')
  expect(formatMb(2048)).toBe('2 GB')
  expect(formatMb(131072)).toBe('128 GB')
  expect(formatMb(null)).toBe('–')
  expect(formatGb(800)).toBe('800 GB')
  expect(formatGb(3800)).toBe('3.8 TB')
  expect(formatGb(undefined)).toBe('–')
})

test('names', () => {
  expect(osName('macos')).toBe('macOS')
  expect(osName('plan9')).toBe('–')
  expect(archName('aarch64')).toBe('ARM')
  expect(archName('arm64')).toBe('ARM')
  expect(archName('x86_64')).toBe('x86')
  expect(archName(null)).toBe('–')
})

test('usedPercent', () => {
  expect(usedPercent(25, 100)).toBe(75)
  expect(usedPercent(0, 100)).toBe(100)
  expect(usedPercent(150, 100)).toBe(0)
  expect(usedPercent(null, 100)).toBe(null)
  expect(usedPercent(10, 0)).toBe(null)
})

test('nameProblem matches the Root rule', () => {
  expect(nameProblem('mac-mini')).toBe(null)
  expect(nameProblem('0abc')).toBe(null)
  for (const bad of ['', 'Upper', 'has space', '-lead', 'semi;colon', '../x', 'a'.repeat(64), "x'; DROP TABLE machines;--", '<script>']) {
    expect(nameProblem(bad)).not.toBe(null)
  }
})

// The same cases as the parent's MachineDisplayNameTests, so the page and the Root agree.
const LEGAL_MACHINE_NAMES = ['Mac Studio', "Luca's PC (RTX)", 'mac-mini', 'R&D box_2.0', 'Ünïcode Café', '1', 'a', 'x'.repeat(48)]
const REFUSED_MACHINE_NAMES = ['', ' ', ' lead', 'trail ', 'two  spaces', 'a\tb', 'line\nbreak', 'nul\u0000byte', '<b>x</b>', 'a"b', 'a`b', 'a$b', 'a;b', 'a/b', 'a\\b', 'a{b}', 'a|b',
  'a b"c\';rm -rf ~;', '...', '- - -', '😀', 'Mac 😀', 'x'.repeat(49), 'a:b', 'a=b', 'a%b']

test('machineNameProblem accepts what the parent accepts', () => {
  for (const name of LEGAL_MACHINE_NAMES) expect(machineNameProblem(name)).toBe(null)
})

test('machineNameProblem refuses what the parent refuses, in plain words', () => {
  for (const name of REFUSED_MACHINE_NAMES) expect(machineNameProblem(name)).not.toBe(null)
  expect(machineNameProblem('a;b')).toBe("Use letters, numbers, spaces and - _ . ( ) ' &, up to 48 characters.")
  expect(machineNameProblem('')).toBe('Give the machine a name.')
})

test('source messages', () => {
  expect(sourceProblem('ok')).toBe(null)
  expect(sourceProblem('refused_401') ?? '').toMatch(/login refused/)
  expect(sourceProblem('refused_500')).toBe('refused (500)')
  expect(sourceProblem('missing')).toBe('not installed')
  expect(sourceProblem('something-new')).toBe('did not run')
  expect(sourceName('agent_probe')).toBe('Agent check')
})

const good = { name: 'demo', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: '' }

test('workload form rules match the Root', () => {
  expect(workloadProblem(good)).toBe(null)
  expect(workloadProblem({ ...good, ramGb: 0.5 })).toBe(null)
  for (const change of [{ name: 'Bad Name' }, { name: '' }, { kind: 'metal' }, { cpu: 0 }, { cpu: 65 }, { cpu: 1.5 }, { ramGb: 0.4 }, { ramGb: 'lots' }, { diskGb: 0 }, { diskGb: 100001 }, { diskGb: 2.5 }]) {
    expect(workloadProblem({ ...good, ...change })).not.toBe(null)
  }
})

test('workload body is what the Root expects', () => {
  expect(workloadBody(good)).toEqual({ name: 'demo', kind: 'vm', cpu: 2, ram_mb: 2048, disk_gb: 20 })
  expect(workloadBody({ ...good, machine: 'dgx', ramGb: 0.5 })).toEqual({ name: 'demo', kind: 'vm', cpu: 2, ram_mb: 512, disk_gb: 20, machine: 'dgx' })
  expect(workloadBody({ ...good, gpuMode: 'none' })).toEqual({ name: 'demo', kind: 'vm', cpu: 2, ram_mb: 2048, disk_gb: 20 })
  expect(workloadBody({ ...good, kind: 'container', gpuMode: 'container', machine: 'rtx' })).toEqual({ name: 'demo', kind: 'container', cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'container', machine: 'rtx' })
  expect(workloadBody({ ...good, kind: 'vm', gpuMode: 'container' })).not.toHaveProperty('gpu_mode')
})

test('the image is sent as bundle only when it is not Blank, and the page never sends an image name', () => {
  expect(workloadBody({ ...good, bundle: 'blank' })).not.toHaveProperty('bundle')
  expect(workloadBody(good)).not.toHaveProperty('bundle')
  expect(workloadBody({ ...good, bundle: 'openclaw', machine: 'mini' })).toEqual({ name: 'demo', kind: 'vm', cpu: 2, ram_mb: 2048, disk_gb: 20, bundle: 'openclaw', machine: 'mini' })
  expect(workloadBody({ ...good, bundle: 'blank' })).not.toHaveProperty('image')
  expect(workloadBody({ ...good, bundle: 'openclaw' })).not.toHaveProperty('image')
})

test('command outcomes', () => {
  expect(commandOutcome(command({ state: 'running' }))).toBe('working…')
  expect(commandOutcome(command({ state: 'failed', result: { error: 'no room' } }))).toBe('no room')
  expect(commandOutcome(command({ state: 'failed' }))).toBe('failed')
  expect(commandOutcome(command({ state: 'succeeded', result: { backup_id: 'w-1.tar' } }))).toBe('backup kept: w-1.tar')
  expect(commandOutcome(command({ state: 'succeeded', result: { backup_id: 'none' } }))).toBe('done')
  expect(commandName('delete')).toBe('Delete')
  expect(commandName('odd')).toBe('odd')
})

test('bundle flags', () => {
  expect(bundleFlag(null, '0.2.0')).toEqual({ text: 'no chat', stale: false })
  expect(bundleFlag('0.2.0', '0.2.0')).toEqual({ text: 'chat 0.2.0', stale: false })
  expect(bundleFlag('0.1.0', '0.2.0')).toEqual({ text: 'chat 0.1.0, needs 0.2.0', stale: true })
  expect(bundleFlag('0.1.0', null)).toEqual({ text: 'chat 0.1.0', stale: false })
})

