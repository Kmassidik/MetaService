import test from 'node:test'
import assert from 'node:assert/strict'
import { addBody, advancedProblem, connectionText, defaultAddChoices, emptyConnectForm, groupedFingerprint, isolationText, loginProblem, nameWrong, planBody, portOf, probeBody, removeBody, suggestMachineName, verifyBody, whereProblem } from './remote.ts'
import type { RemoteMachineInfo, VerifyResult } from './types.ts'

const form = (extra = {}) => ({ ...emptyConnectForm('192.168.100.40'), user: 'kurnia', password: 'secret', ...extra })

test('a good address and port have no problem, a bad one says what to type', () => {
  assert.equal(whereProblem(form()), null)
  assert.equal(whereProblem(form({ host: 'office-mini.local' })), null)
  for (const host of ['', ' ', 'a b', '-oProxyCommand=x', 'a;b', 'a/b']) assert.match(whereProblem(form({ host })) ?? '', /address/, host)
  for (const port of ['', '0', '65536', 'ssh', '22.5']) assert.match(whereProblem(form({ port })) ?? '', /port/, port)
})

test('the login needs a user and either a password or the key', () => {
  assert.equal(loginProblem(form()), null)
  assert.equal(loginProblem(form({ password: '', useKey: true })), null)
  assert.match(loginProblem(form({ user: '' })) ?? '', /user name/)
  assert.match(loginProblem(form({ user: '-oProxyCommand=x' })) ?? '', /user name/)
  assert.match(loginProblem(form({ password: '' })) ?? '', /password/)
  assert.match(loginProblem(form({ password: 'x'.repeat(257) })) ?? '', /too long/)
})

test('the port defaults to 22 and must be a whole number in range', () => {
  assert.equal(portOf(emptyConnectForm()), 22)
  assert.equal(portOf(form({ port: '2222' })), 2222)
  assert.equal(portOf(form({ port: 'abc' })), null)
  assert.deepEqual(probeBody(form({ host: ' 10.0.0.5 ', port: '2222' })), { host: '10.0.0.5', port: 2222 })
})

test('a password login sends the password and not the key flag', () => {
  assert.deepEqual(verifyBody(form(), 'SHA256:abc'), { host: '192.168.100.40', port: 22, user: 'kurnia', fingerprint: 'SHA256:abc', password: 'secret' })
})

test('a key login sends the key flag and never a password, even if one was typed before', () => {
  const body = verifyBody(form({ useKey: true, password: 'left over' }), 'SHA256:abc')
  assert.deepEqual(body, { host: '192.168.100.40', port: 22, user: 'kurnia', fingerprint: 'SHA256:abc', use_key: true })
  assert.equal(JSON.stringify(body).includes('left over'), false)
})

test('the fingerprint is shown in groups of eight and keeps its kind', () => {
  assert.equal(groupedFingerprint('SHA256:viJuXwpW2hjHvK0w4RKrDuXNL+7r2KuOlPC3VkPukWY'), 'SHA256:viJuXwpW 2hjHvK0w 4RKrDuXN L+7r2KuO lPC3VkPu kWY')
  assert.equal(groupedFingerprint('nonsense'), 'nonsense:')
})

test('each isolation level is explained in plain words', () => {
  assert.match(isolationText('folder'), /No admin rights/)
  assert.match(isolationText('dedicated_user'), /admin rights \(sudo\)/)
  assert.equal(isolationText('other'), 'other')
})

const result = (os = 'Darwin') => ({ host: 'x', fingerprint: 'SHA256:abc', facts: { os, arch: 'arm64', version: 'v', chip: 'c', user: 'kurnia', home: '/Users/kurnia', cpu_cores: 8, ram_mb: 16384, disk_free_gb: 100 },
  requirements: [], can_add: true, isolation: ['folder'], system: 's' }) as VerifyResult

test('a machine name is suggested from the address or the host name', () => {
  assert.equal(suggestMachineName('Office-Mini.local'), 'office-mini')
  assert.equal(suggestMachineName('192.168.100.50'), '192-168-100-50')
  assert.equal(suggestMachineName('---'), 'new-machine')
  assert.equal(suggestMachineName('a'.repeat(100)).length, 63)
  assert.equal(nameWrong('office-mini'), null)
  assert.match(nameWrong('Office Mini') ?? '', /lowercase/)
  assert.deepEqual(defaultAddChoices('office-mini.local'), { name: 'office-mini', installKey: true, box: '', sshDir: '', agentPort: '' })
})

test('the plan request carries the home folder and the system that Connect read, and no login', () => {
  const body = planBody(form(), result(), { name: 'office-mini', installKey: true, box: '', sshDir: '', agentPort: '' })
  assert.deepEqual(body, { host: '192.168.100.40', home: '/Users/kurnia', os: 'Darwin', name: 'office-mini', install_key: true })
  assert.equal(JSON.stringify(body).includes('secret'), false)
  assert.equal(planBody(form(), result('Linux'), { ...defaultAddChoices('x'), installKey: false }).os, 'Linux')
  assert.equal(planBody(form(), result('FreeBSD'), { ...defaultAddChoices('x'), installKey: false }).os, 'Linux', 'only the two systems the control panel knows are sent')
})

test('the install request is the login of Connect plus the choices', () => {
  assert.deepEqual(addBody(form(), 'SHA256:abc', { ...defaultAddChoices('office-mini'), installKey: false }), { host: '192.168.100.40', port: 22, user: 'kurnia', fingerprint: 'SHA256:abc', password: 'secret', name: 'office-mini', install_key: false })
  const withKey = addBody(form({ useKey: true, password: 'left over' }), 'SHA256:abc', defaultAddChoices('office-mini'))
  assert.equal(withKey.use_key, true)
  assert.equal(JSON.stringify(withKey).includes('left over'), false)
})

test('removing logs in again, or only forgets', () => {
  assert.deepEqual(removeBody(form(), false), { password: 'secret' })
  assert.deepEqual(removeBody(form({ useKey: true }), false), { use_key: true })
  assert.deepEqual(removeBody(form(), true), { forget_only: true })
})

test('advanced choices are sent only when typed, and are checked like the control panel checks them', () => {
  const typed = { ...defaultAddChoices('office-mini'), box: '/opt/ms/box', sshDir: '/opt/ms/.ssh', agentPort: '9111' }
  assert.equal(advancedProblem(typed), null)
  assert.deepEqual(planBody(form(), result(), typed), { host: '192.168.100.40', home: '/Users/kurnia', os: 'Darwin', name: 'office-mini', install_key: true, box: '/opt/ms/box', ssh_dir: '/opt/ms/.ssh', agent_port: 9111 })
  assert.equal(advancedProblem(defaultAddChoices('x')), null, 'empty means the defaults')
  for (const bad of [{ box: 'relative' }, { box: '/a b' }, { box: '/a/../b' }, { sshDir: '~/.ssh' }, { agentPort: '80' }, { agentPort: '65001' }, { agentPort: 'nine' }]) {
    assert.notEqual(advancedProblem({ ...defaultAddChoices('x'), ...bad }), null, JSON.stringify(bad))
  }
  assert.equal('box' in planBody(form(), result(), defaultAddChoices('x')), false)
})

const info = (tunnel?: RemoteMachineInfo['tunnel']): RemoteMachineInfo => ({ machine: 'm', host: 'h', ssh_port: 22, ssh_user: 'u', level: 'folder', box: '/b', agent_port: 9101, engine: 'apple', has_key: true, tunnel })

test('the connection of a machine installed over SSH is said in one plain line', () => {
  const now = Date.parse('2026-10-12T12:00:00Z')
  const since = '2026-10-12T11:55:00Z'
  assert.equal(connectionText(info({ state: 'connected', since, local_port: 50000, failures: 0 }), now), 'SSH tunnel · connected 5m ago')
  assert.equal(connectionText(info({ state: 'connecting', since, local_port: null, failures: 0 }), now), 'SSH tunnel · connecting…')
  assert.equal(connectionText(info({ state: 'disconnected', since, local_port: null, failures: 1 }), now), 'SSH tunnel · down since 5m ago, trying again')
  assert.equal(connectionText(info({ state: 'disconnected', since, local_port: null, failures: 3 }), now), 'SSH tunnel · down since 5m ago, trying again (3 tries)')
  assert.match(connectionText(info(undefined), now), /No tunnel/)
})
