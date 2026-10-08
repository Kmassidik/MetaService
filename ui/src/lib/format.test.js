import test from 'node:test'
import assert from 'node:assert/strict'
import { relativeTime, formatMb, formatGb, osName, archName, usedPercent, summarize, nameProblem } from './format.js'

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
