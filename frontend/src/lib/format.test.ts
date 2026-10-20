import test from 'node:test'
import assert from 'node:assert/strict'
import { relativeTime, formatMb, formatGb, osName, archName, usedPercent, nameProblem, sourceProblem, sourceName, workloadProblem, workloadBody, commandOutcome, commandName, bundleFlag } from './format.ts'
import { command } from './testing.ts'

const now = Date.parse('2026-10-09T12:00:00Z')
const ago = (ms: number) => new Date(now - ms).toISOString()

test('relativeTime', () => {
  assert.equal(relativeTime(null, now), 'never')
  assert.equal(relativeTime('nonsense', now), 'unknown')
  assert.equal(relativeTime(ago(1000), now), 'just now')
  assert.equal(relativeTime(ago(12_000), now), '12s ago')
  assert.equal(relativeTime(ago(5 * 60_000), now), '5m ago')
  assert.equal(relativeTime(ago(3 * 3_600_000), now), '3h ago')
  assert.equal(relativeTime(ago(2 * 86_400_000), now), '2d ago')
  assert.equal(relativeTime(new Date(now + 60_000).toISOString(), now), 'just now', 'a clock a little ahead never shows a negative age')
})

test('sizes', () => {
  assert.equal(formatMb(512), '512 MB')
  assert.equal(formatMb(2048), '2 GB')
  assert.equal(formatMb(131072), '128 GB')
  assert.equal(formatMb(null), '–')
  assert.equal(formatGb(800), '800 GB')
  assert.equal(formatGb(3800), '3.8 TB')
  assert.equal(formatGb(undefined), '–')
})

test('names', () => {
  assert.equal(osName('macos'), 'macOS')
  assert.equal(osName('plan9'), '–')
  assert.equal(archName('aarch64'), 'ARM')
  assert.equal(archName('arm64'), 'ARM')
  assert.equal(archName('x86_64'), 'x86')
  assert.equal(archName(null), '–')
})

test('usedPercent', () => {
  assert.equal(usedPercent(25, 100), 75)
  assert.equal(usedPercent(0, 100), 100)
  assert.equal(usedPercent(150, 100), 0)
  assert.equal(usedPercent(null, 100), null)
  assert.equal(usedPercent(10, 0), null)
})

test('nameProblem matches the Root rule', () => {
  assert.equal(nameProblem('mac-mini'), null)
  assert.equal(nameProblem('0abc'), null)
  for (const bad of ['', 'Upper', 'has space', '-lead', 'semi;colon', '../x', 'a'.repeat(64), "x'; DROP TABLE machines;--", '<script>']) {
    assert.notEqual(nameProblem(bad), null, bad)
  }
})

test('source messages', () => {
  assert.equal(sourceProblem('ok'), null)
  assert.match(sourceProblem('refused_401') ?? '', /login refused/)
  assert.equal(sourceProblem('refused_500'), 'refused (500)')
  assert.equal(sourceProblem('missing'), 'not installed')
  assert.equal(sourceProblem('something-new'), 'did not run')
  assert.equal(sourceName('agent_probe'), 'Agent check')
})

const good = { name: 'demo', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: '' }

test('workload form rules match the Root', () => {
  assert.equal(workloadProblem(good), null)
  assert.equal(workloadProblem({ ...good, ramGb: 0.5 }), null)
  for (const change of [{ name: 'Bad Name' }, { name: '' }, { kind: 'metal' }, { cpu: 0 }, { cpu: 65 }, { cpu: 1.5 }, { ramGb: 0.4 }, { ramGb: 'lots' }, { diskGb: 0 }, { diskGb: 100001 }, { diskGb: 2.5 }]) {
    assert.notEqual(workloadProblem({ ...good, ...change }), null, JSON.stringify(change))
  }
})

test('workload body is what the Root expects', () => {
  assert.deepEqual(workloadBody(good), { name: 'demo', kind: 'vm', cpu: 2, ram_mb: 2048, disk_gb: 20 })
  assert.deepEqual(workloadBody({ ...good, machine: 'dgx', ramGb: 0.5 }), { name: 'demo', kind: 'vm', cpu: 2, ram_mb: 512, disk_gb: 20, machine: 'dgx' })
})

test('command outcomes', () => {
  assert.equal(commandOutcome(command({ state: 'running' })), 'working…')
  assert.equal(commandOutcome(command({ state: 'failed', result: { error: 'no room' } })), 'no room')
  assert.equal(commandOutcome(command({ state: 'failed' })), 'failed')
  assert.equal(commandOutcome(command({ state: 'succeeded', result: { backup_id: 'w-1.tar' } })), 'backup kept: w-1.tar')
  assert.equal(commandOutcome(command({ state: 'succeeded', result: { backup_id: 'none' } })), 'done')
  assert.equal(commandName('delete'), 'Delete')
  assert.equal(commandName('odd'), 'odd')
})

test('bundle flags', () => {
  assert.deepEqual(bundleFlag(null, '0.2.0'), { text: 'no chat', stale: false })
  assert.deepEqual(bundleFlag('0.2.0', '0.2.0'), { text: 'chat 0.2.0', stale: false })
  assert.deepEqual(bundleFlag('0.1.0', '0.2.0'), { text: 'chat 0.1.0, needs 0.2.0', stale: true })
  assert.deepEqual(bundleFlag('0.1.0', null), { text: 'chat 0.1.0', stale: false })
})

