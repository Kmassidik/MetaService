import { test, expect } from 'bun:test'
import { cardUpdate } from './helperUpdate.ts'
import { fixBody, verifyBody } from './remote.ts'
import { offersCardFix, problemHasCheck, recheckForm, recheckProblem } from './recheck.ts'
import { machine } from './testing.ts'
import type { HelperUpdateInfo, Machine, Problem, RemoteMachineInfo } from './types.ts'

const OLD_BUILD = 'a'.repeat(64)
const NEW_BUILD = 'b'.repeat(64)
const updateInfo = (extra: Partial<HelperUpdateInfo> = {}): HelperUpdateInfo => ({ available: true, current_build: OLD_BUILD, newest_build: NEW_BUILD, reason: null, ...extra })

const info = (extra: Partial<RemoteMachineInfo> = {}): RemoteMachineInfo => ({
  machine: 'office-mini',
  host: '192.168.100.40',
  ssh_port: 2222,
  ssh_user: 'kurnia',
  level: 'folder',
  box: '/home/kurnia/metaservice-box',
  agent_port: 9101,
  engine: 'incus',
  has_key: true,
  ...extra,
})

test('a re-check starts from the record: where it is, its port and its user, never a password', () => {
  expect(recheckForm(info())).toEqual({ host: '192.168.100.40', port: '2222', user: 'kurnia', password: '', useKey: false, machineId: 'office-mini' })
})

test('a machine the parent did not add over SSH says why it cannot be checked', () => {
  expect(recheckProblem(info())).toBeNull()
  expect(recheckProblem(null) ?? '').toMatch(/did not add this machine over SSH/)
})

test('a re-check names the machine, and never sends an address or host key again', () => {
  const form = { ...recheckForm(info()), password: 'secret' }
  expect(verifyBody(form, 'SHA256:ignored')).toEqual({ machine: 'office-mini', password: 'secret' })
  expect(verifyBody({ ...form, useKey: true })).toEqual({ machine: 'office-mini', use_key: true })
})

test('Install it for me on a re-check names the same machine, with the password for both login and sudo', () => {
  const form = { ...recheckForm(info()), password: 'secret' }
  expect(fixBody(form, 'SHA256:ignored', { part: 'autostart', needs_password: true }, 'secret'))
    .toEqual({ machine: 'office-mini', password: 'secret', fix: 'autostart', sudo_password: 'secret' })
  expect(fixBody({ ...form, useKey: true }, 'SHA256:ignored', { part: 'vm_packages', needs_password: false }, ''))
    .toEqual({ machine: 'office-mini', use_key: true, fix: 'vm_packages' })
})

test('only a problem the check covers gets an action; anything else gets none', () => {
  for (const code of ['container_service_stopped', 'container_tool_missing', 'incus_unreachable']) expect(problemHasCheck({ code })).toBe(true)
  for (const code of ['bridge_blocked_by_firewall', 'a_new_code', '']) expect(problemHasCheck({ code })).toBe(false)
})

const problem = (code: string): Problem => ({ code, message: 'It is not running.', fix: 'Start it.' })
const held = (extra: Partial<Machine> = {}) => machine({ problems: [problem('container_service_stopped')], ...extra })

test('a card offers Fix for a problem the check covers, and only for those', () => {
  for (const code of ['container_service_stopped', 'container_tool_missing', 'incus_unreachable']) expect(offersCardFix(held({ problems: [problem(code)] }), info())).toBe(true)
  expect(offersCardFix(held(), info())).toBe(true)
})

test('a card offers no Fix for a problem the panel cannot fix, or for none at all', () => {
  for (const code of ['bridge_blocked_by_firewall', 'a_new_code', '']) expect(offersCardFix(held({ problems: [problem(code)] }), info())).toBe(false)
  expect(offersCardFix(machine(), info())).toBe(false)
  expect(offersCardFix(machine({ problems: [] }), info())).toBe(false)
  expect(offersCardFix(held({ problems: [problem('bridge_blocked_by_firewall'), problem('a_new_code')] }), info())).toBe(false)
})

test('a card offers Fix when one of several problems is one the check covers', () => {
  expect(offersCardFix(held({ problems: [problem('bridge_blocked_by_firewall'), problem('incus_unreachable')] }), info())).toBe(true)
})

test('an offline card offers no Fix, and a machine with no saved login offers none either', () => {
  expect(offersCardFix(held({ state: 'offline' }), info())).toBe(false)
  expect(offersCardFix(held(), null)).toBe(false)
})

test('Fix and Update helper live together on one card without either hiding the other', () => {
  const both = machine({ agent_build: OLD_BUILD, update: updateInfo(), problems: [problem('container_service_stopped')] })
  expect(cardUpdate(both).button).toBe(true)
  expect(offersCardFix(both, info())).toBe(true)
  const updateOnly = machine({ agent_build: OLD_BUILD, update: updateInfo() })
  expect(cardUpdate(updateOnly).button).toBe(true)
  expect(offersCardFix(updateOnly, info())).toBe(false)
  const fixOnly = held({ agent_build: NEW_BUILD, update: updateInfo({ available: false }) })
  expect(cardUpdate(fixOnly).button).toBe(false)
  expect(offersCardFix(fixOnly, info())).toBe(true)
})
