import { test, expect } from 'bun:test'
import { CHAT_NOT_PINNED, NO_CHAT_BUILT, NOT_REPORTED, canRunText, compareVersions, engineText, gpuText, helperIsOld, newestVersion, reported, ruvioView, softwareRows, tunnelText } from './environment.ts'
import { machine } from './testing.ts'
import type { RemoteMachineInfo, Ruvio, RuvioState } from './types.ts'

const NOW = Date.parse('2026-10-21T12:00:00Z')
const ruvio = (state: RuvioState, extra: Partial<Ruvio> = {}): Ruvio => ({ installed: null, pinned: '0.4.0', state, ...extra })
const remote = (extra: Partial<RemoteMachineInfo> = {}): RemoteMachineInfo => ({ machine: 'm', host: '10.0.0.5', ssh_port: 22, ssh_user: 'k', level: 'user', box: '~/metaservice-box', agent_port: 8447, engine: 'apple', has_key: true, ...extra })

test('reported shows "not reported" for anything missing, never a guess', () => {
  expect(reported(null)).toBe(NOT_REPORTED)
  expect(reported(undefined)).toBe(NOT_REPORTED)
  expect(reported('')).toBe(NOT_REPORTED)
  expect(reported('0.3.1')).toBe('0.3.1')
  expect(reported(8447)).toBe('8447')
  expect(reported(0)).toBe('0')
})

test('compareVersions orders dotted numbers and refuses text', () => {
  expect(compareVersions('0.3.1', '0.3.1')).toBe(0)
  expect(compareVersions('0.3.1', '0.10.0')).toBeLessThan(0)
  expect(compareVersions('1.0', '0.9.9')).toBeGreaterThan(0)
  expect(compareVersions('1.0', '1.0.0')).toBe(0)
  expect(compareVersions('1.0-beta', '1.0')).toBeNull()
  expect(compareVersions('', '1.0')).toBeNull()
})

test('newestVersion picks the highest and skips missing or unreadable ones', () => {
  expect(newestVersion([])).toBeNull()
  expect(newestVersion([null, undefined, ''])).toBeNull()
  expect(newestVersion(['0.2.0', '0.10.0', '0.9.1'])).toBe('0.10.0')
  expect(newestVersion(['junk', '0.2.0'])).toBe('0.2.0')
})

test('helperIsOld marks only a helper that is behind', () => {
  expect(helperIsOld('0.2.0', '0.3.0')).toBe(true)
  expect(helperIsOld('0.3.0', '0.3.0')).toBe(false)
  expect(helperIsOld('0.4.0', '0.3.0')).toBe(false)
  expect(helperIsOld(null, '0.3.0')).toBe(false)
  expect(helperIsOld('0.2.0', null)).toBe(false)
  expect(helperIsOld('unreadable', '0.3.0')).toBe(false)
})

test('engineText names the engine, its version and whether it is ready', () => {
  expect(engineText({ name: 'apple', version: '1.5.0', ready: true })).toBe('Apple container 1.5.0, ready')
  expect(engineText({ name: 'incus', version: null, ready: false })).toBe('Incus, not ready')
  expect(engineText({ name: 'podman', version: '5', ready: true })).toBe('podman 5, ready')
  expect(engineText(null)).toBe(NOT_REPORTED)
  expect(engineText(undefined)).toBe(NOT_REPORTED)
})

test('canRunText says what the machine can run and what it cannot', () => {
  expect(canRunText({ vm: true, container: true, gpu_in_vm: false, gpu_in_container: false })).toBe('Can run: VMs and containers · GPU in a VM: no · GPU in a container: no')
  expect(canRunText({ vm: true, container: false, gpu_in_vm: true, gpu_in_container: false })).toBe('Can run: VMs · GPU in a VM: yes · GPU in a container: no')
  expect(canRunText({ vm: false, container: false, gpu_in_vm: false, gpu_in_container: false })).toContain('nothing yet')
  expect(canRunText(undefined)).toBe(`Can run: ${NOT_REPORTED}`)
})

test('gpuText lists the GPUs or says none', () => {
  expect(gpuText([])).toBe('none')
  expect(gpuText([{ vendor: 'NVIDIA', model: 'GB10' }, { vendor: 'Apple', model: 'M2' }])).toBe('NVIDIA GB10, Apple M2')
})

test('tunnelText reports the tunnel, or that none is reported', () => {
  expect(tunnelText(null, NOW)).toBe(NOT_REPORTED)
  expect(tunnelText(remote(), NOW)).toContain('No tunnel')
  expect(tunnelText(remote({ tunnel: { state: 'connected', since: '2026-10-21T11:00:00Z', local_port: 9000, failures: 0 } }), NOW)).toBe('SSH tunnel · connected 1h ago')
})

test('softwareRows of the real mac-studio record: nothing is invented', () => {
  const studio = machine({ id: 'mac-studio', name: 'mac-studio', agent_version: null, engine: null, box: null, agent_port: null })
  const rows = softwareRows(studio, null, '0.3.0', NOW)
  expect(rows.map((row) => row.label)).toEqual(['Helper version', 'Engine', 'Helper folder', 'Helper port', 'Tunnel'])
  expect(rows.every((row) => row.value === NOT_REPORTED && !row.old)).toBe(true)
})

test('softwareRows marks an old helper and prints the reported values', () => {
  const old = machine({ agent_version: '0.2.0', engine: { name: 'apple', version: '1.5.0', ready: true }, box: '~/metaservice-box', agent_port: 8447 })
  const rows = softwareRows(old, remote(), '0.3.0', NOW)
  expect(rows[0]).toEqual({ label: 'Helper version', value: '0.2.0', old: true })
  expect(rows[1]?.value).toBe('Apple container 1.5.0, ready')
  expect(rows[2]?.value).toBe('~/metaservice-box')
  expect(rows[3]?.value).toBe('8447')
})

test('ruvioView: off by default can be turned on', () => {
  const view = ruvioView(ruvio('off'), 1, true)
  expect(view).toMatchObject({ on: false, canToggle: true, busy: false, status: 'off', reason: null, canOpen: false })
})

test('ruvioView: nothing pinned and nothing built disables the switch with the parent\'s words', () => {
  const view = ruvioView(ruvio('unavailable', { pinned: null }), 0, true)
  expect(view.canToggle).toBe(false)
  expect(view.reason).toBe(NO_CHAT_BUILT)
  expect(NO_CHAT_BUILT).toBe('no chat is built on the parent')
})

test('ruvioView: several built and none chosen says to choose one', () => {
  expect(ruvioView(ruvio('unavailable', { pinned: null }), 3, true).reason).toBe(CHAT_NOT_PINNED)
})

test('ruvioView: on shows Open chat and can be turned off', () => {
  const view = ruvioView(ruvio('on', { installed: '0.4.0' }), 1, true)
  expect(view).toMatchObject({ on: true, canToggle: true, canOpen: true, canUpdate: false, status: 'on' })
})

test('ruvioView: an old version can be brought up to date', () => {
  const view = ruvioView(ruvio('outdated', { installed: '0.3.0' }), 2, true)
  expect(view).toMatchObject({ on: true, canUpdate: true, canOpen: true })
})

test('ruvioView: while a command goes the switch waits', () => {
  expect(ruvioView(ruvio('installing'), 1, true)).toMatchObject({ on: true, busy: true, canToggle: false })
  expect(ruvioView(ruvio('removing', { installed: '0.4.0' }), 1, true)).toMatchObject({ on: false, busy: true, canToggle: false })
})

test('ruvioView: an offline machine cannot be switched, and does not offer Open chat', () => {
  const view = ruvioView(ruvio('on', { installed: '0.4.0' }), 1, false)
  expect(view).toMatchObject({ canToggle: false, canOpen: false, canUpdate: false })
  expect(view.reason).toBe('the machine is offline')
})

test('ruvioView: before the first report it says so and cannot be pressed', () => {
  expect(ruvioView(null, 1, true)).toMatchObject({ canToggle: false, status: NOT_REPORTED, reason: 'the machine has not reported yet' })
  expect(ruvioView(undefined, 1, true).canToggle).toBe(false)
})
