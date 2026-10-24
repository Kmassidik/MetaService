import { expect, test } from 'bun:test'
import { endsText, durationText, keyState, killCopy, revokeCopy, sandboxStateLabel, sandboxStateTone, shapeText, teamNameProblem, usageTotals, windowLabel } from './sandboxPanel.ts'

const NOW = Date.parse('2026-10-24T09:00:00Z')

test('a team name is checked the way the Root reads it; an empty field means the default team', () => {
  expect(teamNameProblem('')).toBeNull()
  expect(teamNameProblem('   ')).toBeNull()
  expect(teamNameProblem('Our apps')).toBeNull()
  expect(teamNameProblem("Oynenza's tasks")).toBeNull()
  expect(teamNameProblem(' app')).not.toBeNull()
  expect(teamNameProblem('two  spaces')).not.toBeNull()
  expect(teamNameProblem('a/b')).not.toBeNull()
  expect(teamNameProblem('a'.repeat(49))).not.toBeNull()
})

test('every state has plain words and a colour', () => {
  expect(['starting', 'running', 'paused', 'ended'].map(sandboxStateLabel)).toEqual(['Starting', 'Running', 'Paused', 'Ended'])
  expect(sandboxStateLabel('nonsense')).toBe('Unknown')
  expect(sandboxStateTone('running')).toBe('run')
  expect(sandboxStateTone('paused')).toBe('warn')
  expect(sandboxStateTone('starting')).toBe('act')
  expect(sandboxStateTone('ended')).toBe('')
})

test('the end time reads as the time left, and as due once it has passed', () => {
  expect(endsText('2026-10-24T09:04:00Z', NOW)).toBe('in 4m')
  expect(endsText('2026-10-24T09:00:30Z', NOW)).toBe('in 30s')
  expect(endsText('2026-10-24T10:05:00Z', NOW)).toBe('in 1h 5m')
  expect(endsText('2026-10-24T08:59:00Z', NOW)).toBe('any moment')
  expect(endsText('not a time', NOW)).toBe('unknown')
})

test('a shape is said in the panel\'s short words', () => {
  expect(shapeText(2, 512, 10240)).toBe('2 vCPU · 512 MB · 10 GB')
  expect(shapeText(4, 2048, 20480)).toBe('4 vCPU · 2 GB · 20 GB')
})

test('a counted number of seconds is said in minutes, hours and days', () => {
  expect([0, 45, 660, 3660, 90_000].map(durationText)).toEqual(['0s', '45s', '11m', '1h 1m', '1d 1h'])
  expect(durationText(-5)).toBe('0s')
})

test('a key is active until it is revoked', () => {
  expect(keyState(null)).toBe('Active')
  expect(keyState('2026-10-24T09:00:00Z')).toBe('Revoked')
})

test('the usage window is said in days', () => {
  expect([1, 7, 30].map(windowLabel)).toEqual(['Last 1 day', 'Last 7 days', 'Last 30 days'])
})

test('the totals line adds every team up', () => {
  expect(usageTotals([{ sandboxes: 2, seconds: 10, vcpu_seconds: 20, ram_mb_seconds: 30 }, { sandboxes: 1, seconds: 5, vcpu_seconds: 6, ram_mb_seconds: 7 }]))
    .toEqual({ sandboxes: 3, seconds: 15, vcpu_seconds: 26, ram_mb_seconds: 37 })
  expect(usageTotals([])).toEqual({ sandboxes: 0, seconds: 0, vcpu_seconds: 0, ram_mb_seconds: 0 })
})

test('the confirm dialogs name what goes and what is lost', () => {
  expect(killCopy({ id: 'abc123', template: 'base', team_name: 'Our apps' })).toEqual({
    title: 'Kill this sandbox?',
    what: 'Sandbox abc123 (base, team Our apps) stops now.',
    consequence: 'Everything inside it is lost: its files, its running programs and its memory. It cannot be started again.',
    confirmLabel: 'Kill sandbox',
  })
  expect(revokeCopy({ prefix: 'msb_ab12cd34', team_name: 'Our apps' }).confirmLabel).toBe('Revoke key')
  expect(revokeCopy({ prefix: 'msb_ab12cd34', team_name: 'Our apps' }).what).toContain('msb_ab12cd34')
})
