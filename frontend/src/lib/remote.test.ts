import { test, expect } from 'bun:test'
import { keyCommand, passwordAccepted, addBody, advancedProblem, connectionText, defaultAddChoices, emptyConnectForm, groupedFingerprint, isolationText, loginProblem, nameWrong, planBody, portOf, probeBody, removeBody, suggestMachineName, userWarning, verifyBody, whereProblem } from './remote.ts'
import type { RemoteMachineInfo, VerifyResult } from './types.ts'

const form = (extra = {}) => ({ ...emptyConnectForm('192.168.100.40'), user: 'kurnia', password: 'secret', ...extra })

test('a good address and port have no problem, a bad one says what to type', () => {
  expect(whereProblem(form())).toBe(null)
  expect(whereProblem(form({ host: 'office-mini.local' }))).toBe(null)
  for (const host of ['', ' ', 'a b', '-oProxyCommand=x', 'a;b', 'a/b']) expect(whereProblem(form({ host })) ?? '').toMatch(/address/)
  for (const port of ['', '0', '65536', 'ssh', '22.5']) expect(whereProblem(form({ port })) ?? '').toMatch(/port/)
})

test('a user name with a space is warned about while typing, an empty or good one is not', () => {
  expect(userWarning('dalang mac') ?? '').toMatch(/spaces/)
  expect(userWarning('9lives') ?? '').toMatch(/letters/)
  expect(userWarning('')).toBeNull()
  expect(userWarning('kurnia')).toBeNull()
})

test('the login needs a user and either a password or the key', () => {
  expect(loginProblem(form())).toBe(null)
  expect(loginProblem(form({ password: '', useKey: true }))).toBe(null)
  expect(loginProblem(form({ user: '' })) ?? '').toMatch(/user name/)
  expect(loginProblem(form({ user: '-oProxyCommand=x' })) ?? '').toMatch(/user name/)
  expect(loginProblem(form({ password: '' })) ?? '').toMatch(/password/)
  expect(loginProblem(form({ password: 'x'.repeat(257) })) ?? '').toMatch(/too long/)
})

test('the port defaults to 22 and must be a whole number in range', () => {
  expect(portOf(emptyConnectForm())).toBe(22)
  expect(portOf(form({ port: '2222' }))).toBe(2222)
  expect(portOf(form({ port: 'abc' }))).toBe(null)
  expect(probeBody(form({ host: ' 10.0.0.5 ', port: '2222' }))).toEqual({ host: '10.0.0.5', port: 2222 })
})

test('a password login sends the password and not the key flag', () => {
  expect(verifyBody(form(), 'SHA256:abc')).toEqual({ host: '192.168.100.40', port: 22, user: 'kurnia', fingerprint: 'SHA256:abc', password: 'secret' })
})

test('a key login sends the key flag and never a password, even if one was typed before', () => {
  const body = verifyBody(form({ useKey: true, password: 'left over' }), 'SHA256:abc')
  expect(body).toEqual({ host: '192.168.100.40', port: 22, user: 'kurnia', fingerprint: 'SHA256:abc', use_key: true })
  expect(JSON.stringify(body).includes('left over')).toBe(false)
})

test('the fingerprint is shown in groups of eight and keeps its kind', () => {
  expect(groupedFingerprint('SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY')).toBe('SHA256:viJuXwpW 2hjHvK0w 4RKrDuXN L+7r2KuO lPC3VkPu kWY')
  expect(groupedFingerprint('nonsense')).toBe('nonsense:')
})

test('each isolation level is explained in plain words', () => {
  expect(isolationText('folder')).toMatch(/No admin rights/)
  expect(isolationText('dedicated_user')).toMatch(/admin rights \(sudo\)/)
  expect(isolationText('other')).toBe('other')
})

const result = (os = 'Darwin') => ({ host: 'x', fingerprint: 'SHA256:abc', facts: { os, arch: 'arm64', version: 'v', chip: 'c', user: 'kurnia', home: '/Users/kurnia', cpu_cores: 8, ram_mb: 16384, disk_free_gb: 100 },
  requirements: [], can_add: true, isolation: ['folder'], system: 's' }) as VerifyResult

test('a machine name is suggested from the address or the host name', () => {
  expect(suggestMachineName('Office-Mini.local')).toBe('office-mini')
  expect(suggestMachineName('192.168.100.50')).toBe('192-168-100-50')
  expect(suggestMachineName('---')).toBe('new-machine')
  expect(suggestMachineName('a'.repeat(100)).length).toBe(63)
  expect(nameWrong('office-mini')).toBe(null)
  expect(nameWrong('Office Mini') ?? '').toMatch(/lowercase/)
  expect(defaultAddChoices('office-mini.local')).toEqual({ name: 'office-mini', installKey: true, box: '', sshDir: '', agentPort: '' })
})

test('the plan request carries the home folder and the system that Connect read, and no login', () => {
  const body = planBody(form(), result(), { name: 'office-mini', installKey: true, box: '', sshDir: '', agentPort: '' })
  expect(body).toEqual({ host: '192.168.100.40', home: '/Users/kurnia', os: 'Darwin', name: 'office-mini', install_key: true })
  expect(JSON.stringify(body).includes('secret')).toBe(false)
  expect(planBody(form(), result('Linux'), { ...defaultAddChoices('x'), installKey: false }).os).toBe('Linux')
  expect(planBody(form(), result('FreeBSD'), { ...defaultAddChoices('x'), installKey: false }).os).toBe('Linux')
})

test('the install request is the login of Connect plus the choices', () => {
  expect(addBody(form(), 'SHA256:abc', { ...defaultAddChoices('office-mini'), installKey: false })).toEqual({ host: '192.168.100.40', port: 22, user: 'kurnia', fingerprint: 'SHA256:abc', password: 'secret', name: 'office-mini', install_key: false })
  const withKey = addBody(form({ useKey: true, password: 'left over' }), 'SHA256:abc', defaultAddChoices('office-mini'))
  expect(withKey.use_key).toBe(true)
  expect(JSON.stringify(withKey).includes('left over')).toBe(false)
})

test('removing logs in again, or only forgets', () => {
  expect(removeBody(form(), false)).toEqual({ password: 'secret' })
  expect(removeBody(form({ useKey: true }), false)).toEqual({ use_key: true })
  expect(removeBody(form(), true)).toEqual({ forget_only: true })
})

test('advanced choices are sent only when typed, and are checked like the control panel checks them', () => {
  const typed = { ...defaultAddChoices('office-mini'), box: '/opt/ms/box', sshDir: '/opt/ms/.ssh', agentPort: '9111' }
  expect(advancedProblem(typed)).toBe(null)
  expect(planBody(form(), result(), typed)).toEqual({ host: '192.168.100.40', home: '/Users/kurnia', os: 'Darwin', name: 'office-mini', install_key: true, box: '/opt/ms/box', ssh_dir: '/opt/ms/.ssh', agent_port: 9111 })
  expect(advancedProblem(defaultAddChoices('x'))).toBe(null)
  for (const bad of [{ box: 'relative' }, { box: '/a b' }, { box: '/a/../b' }, { sshDir: '~/.ssh' }, { agentPort: '80' }, { agentPort: '65001' }, { agentPort: 'nine' }]) {
    expect(advancedProblem({ ...defaultAddChoices('x'), ...bad })).not.toBe(null)
  }
  expect('box' in planBody(form(), result(), defaultAddChoices('x'))).toBe(false)
})

const info = (tunnel?: RemoteMachineInfo['tunnel']): RemoteMachineInfo => ({ machine: 'm', host: 'h', ssh_port: 22, ssh_user: 'u', level: 'folder', box: '/b', agent_port: 9101, engine: 'apple', has_key: true, ...(tunnel === undefined ? {} : { tunnel }) })

test('the connection of a machine installed over SSH is said in one plain line', () => {
  const now = Date.parse('2026-10-12T12:00:00Z')
  const since = '2026-10-12T11:55:00Z'
  expect(connectionText(info({ state: 'connected', since, local_port: 50000, failures: 0 }), now)).toBe('SSH tunnel · connected 5m ago')
  expect(connectionText(info({ state: 'connecting', since, local_port: null, failures: 0 }), now)).toBe('SSH tunnel · connecting…')
  expect(connectionText(info({ state: 'disconnected', since, local_port: null, failures: 1 }), now)).toBe('SSH tunnel · down since 5m ago, trying again')
  expect(connectionText(info({ state: 'disconnected', since, local_port: null, failures: 3 }), now)).toBe('SSH tunnel · down since 5m ago, trying again (3 tries)')
  expect(connectionText(info(undefined), now)).toMatch(/No tunnel/)
})

test('a password box is offered unless the computer said it takes only keys', () => {
  expect(passwordAccepted(undefined)).toBe(true)
  expect(passwordAccepted(null)).toBe(true)
  expect(passwordAccepted([])).toBe(true)
  expect(passwordAccepted(['publickey', 'password'])).toBe(true)
  expect(passwordAccepted(['publickey', 'keyboard-interactive'])).toBe(true)
  expect(passwordAccepted(['publickey'])).toBe(false)
})

test('the key command adds the key once and refuses anything that is not a plain key', () => {
  const key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJwjwIYPmV4ChyokDCF+LCmk3pi0LkdCycg7KQ4h1+u/ metaservice-parent'
  const command = keyCommand(`${key}\n`) ?? ''
  expect(command).toMatch(/^mkdir -p ~\/\.ssh && chmod 700 ~\/\.ssh && \(grep -qxF '/)
  expect(command).toMatch(/chmod 600 ~\/\.ssh\/authorized_keys/)
  expect(command.split(key).length - 1).toBe(2)
  for (const bad of ['', "ssh-ed25519 AAAA'; rm -rf ~; '", 'ssh-rsa AAAA x', 'ssh-ed25519 AAAA x\nssh-ed25519 BBBB y', "ssh-ed25519 AAAA $(id)"]) expect(keyCommand(bad)).toBe(null)
})
