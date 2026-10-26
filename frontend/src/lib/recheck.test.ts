import { test, expect } from 'bun:test'
import { fixBody, verifyBody } from './remote.ts'
import { problemHasCheck, recheckForm, recheckProblem } from './recheck.ts'
import type { RemoteMachineInfo } from './types.ts'

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
