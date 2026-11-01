import { expect, test } from 'bun:test'
import { INSTALL_ANYWAY, NO_KEY_LINE, UNKNOWN_HERE, hardenSteps, lacksKey, verifyRows, warningTotal } from './verifySecurity.ts'
import type { VerifySecurity } from './types.ts'

const fresh: VerifySecurity = { password_login: true, ban_tool: 'not_running', firewall: false, auto_updates: false, pending_updates: 4, has_key_login: true }
const good: VerifySecurity = { password_login: false, ban_tool: 'running', firewall: true, auto_updates: true, pending_updates: 0, has_key_login: true }
const nothing: VerifySecurity = { password_login: null, ban_tool: null, firewall: null, auto_updates: null, pending_updates: null, has_key_login: null }

test('a fresh machine has five warnings and no row that needs the helper', () => {
  const rows = verifyRows(fresh)
  expect(rows.map((row) => row.id)).toEqual(['password_login', 'ban_tool', 'firewall', 'auto_updates', 'pending_updates'])
  expect(rows.every((row) => row.state === 'warning')).toBe(true)
  expect(warningTotal(rows)).toBe(5)
  expect(rows[0]?.line).toContain('Anyone on the internet can keep guessing it')
  expect(rows[1]?.line).toContain('No ban tool')
  expect(rows[2]?.line).toContain('The firewall is off')
  expect(rows[4]?.line).toBe('4 security updates are waiting.')
})

test('a hardened machine is all ok', () => {
  const rows = verifyRows(good)
  expect(rows.every((row) => row.state === 'ok')).toBe(true)
  expect(warningTotal(rows)).toBe(0)
})

test('unknown stays unknown in this step\'s own words, never ok and never a warning', () => {
  const rows = verifyRows(nothing)
  expect(rows.every((row) => row.state === 'unknown' && row.line === UNKNOWN_HERE)).toBe(true)
})

test('a Mac has no ban tool to wish for: it is not a warning', () => {
  const row = verifyRows({ ...good, ban_tool: 'not_available' })[1]
  expect(row?.state).toBe('unknown')
  expect(row?.short).toBe('n/a')
})

test('one security update is said in the singular', () => {
  expect(verifyRows({ ...good, pending_updates: 1 })[4]?.line).toBe('1 security update is waiting.')
})

test('the red line is only for a machine that said it has no key', () => {
  expect(lacksKey({ ...fresh, has_key_login: false })).toBe(true)
  expect(lacksKey(fresh)).toBe(false)
  expect(lacksKey(nothing)).toBe(false)
  expect(NO_KEY_LINE).toBe('No SSH key is installed for this user: do not turn off password login yet')
})

test('the install is never held back: the sentence says so', () => {
  expect(INSTALL_ANYWAY).toBe('You can install now and harden afterwards: the Security page keeps showing these rows.')
})

test('the commands copied are the scripts of scripts/harden for the right system', () => {
  expect(hardenSteps('Linux').map((step) => step.command)).toEqual(['./harden-linux.sh check', 'sudo ./harden-linux.sh apply --confirm-key-login', 'sudo ./harden-linux.sh confirm'])
  expect(hardenSteps('Darwin').map((step) => step.command)).toEqual(['./harden-mac.sh check', 'sudo ./harden-mac.sh apply --confirm-key-login', 'sudo ./harden-mac.sh confirm'])
})
