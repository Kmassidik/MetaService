import test from 'node:test'
import assert from 'node:assert/strict'
import { relativeTime, formatMb, formatGb, osName, archName, usedPercent, summarize, nameProblem, suggestName, sourceProblem, sourceName } from './format.js'

const now = Date.parse('2026-10-09T12:00:00Z')
const ago = (ms) => new Date(now - ms).toISOString()

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

test('summarize', () => {
  const machines = [{ state: 'online', workloads: [1, 2] }, { state: 'busy', workloads: [] }, { state: 'offline', workloads: [3] }]
  assert.deepEqual(summarize(machines), { machines: 3, online: 2, workloads: 3 })
  assert.deepEqual(summarize([]), { machines: 0, online: 0, workloads: 0 })
})

test('nameProblem matches the Root rule', () => {
  assert.equal(nameProblem('mac-mini'), null)
  assert.equal(nameProblem('0abc'), null)
  for (const bad of ['', 'Upper', 'has space', '-lead', 'semi;colon', '../x', 'a'.repeat(64), "x'; DROP TABLE machines;--", '<script>']) {
    assert.notEqual(nameProblem(bad), null, bad)
  }
})

test('suggestName always gives a name the Root accepts', () => {
  assert.equal(suggestName('Kurnias-MacBook-Pro.local', '192.168.100.40'), 'kurnias-macbook-pro-local')
  assert.equal(suggestName(null, '192.168.100.60'), 'device-60')
  assert.equal(suggestName('', '192.168.100.61'), 'device-61')
  assert.equal(suggestName('<script>alert(1)</script>', '192.168.100.62'), 'script-alert-1-script')
  assert.equal(suggestName('---', '192.168.100.63'), 'device-63')
  assert.equal(suggestName('x'.repeat(100), '192.168.100.64').length, 63)
  for (const hostname of ['Ünïcode', 'a b c', "x'; DROP TABLE machines;--", '../../etc', '-lead', 'UPPER']) {
    assert.equal(nameProblem(suggestName(hostname, '192.168.100.9')), null, hostname)
  }
})

test('source messages', () => {
  assert.equal(sourceProblem('ok'), null)
  assert.match(sourceProblem('refused_401'), /login refused/)
  assert.equal(sourceProblem('refused_500'), 'refused (500)')
  assert.equal(sourceProblem('missing'), 'not installed')
  assert.equal(sourceProblem('something-new'), 'did not run')
  assert.equal(sourceName('agent_probe'), 'Agent check')
})
