import { expect, test } from 'bun:test'
import { parseJoinCommand, parsePeers, parsePending, parseSupported } from './share.ts'
import { UnreadableAnswer } from './unreadable.ts'

const pendingRow = (extra: Record<string, unknown> = {}) => ({
  id: 'p1', hostname: 'far-mac', os: 'mac', cpu: 'arm64', share: { cores: 4, ram_mb: 8192, disk_gb: 100 },
  created_at: '2026-10-31T10:00:00Z', expires_at: '2026-10-31T10:15:00Z', tries_left: 5, ...extra,
})
const peerRow = (extra: Record<string, unknown> = {}) => ({ name: 'far-mac', address: '10.77.0.2', public_key: 'AbCdEfGh', os: 'mac', cpu: 'arm64', last_handshake_secs_ago: 12, ...extra })

test('the supported table is read into the three systems and their CPU states', () => {
  const table = parseSupported([
    { os: 'mac', cpus: [{ cpu: 'arm64', state: 'ready' }, { cpu: 'x86_64', state: 'untested' }] },
    { os: 'windows', cpus: [{ cpu: 'x86_64', state: 'soon' }] },
    { os: 'linux', cpus: [{ cpu: 'x86_64', state: 'missing' }] },
  ])
  expect(table.map((row) => row.os)).toEqual(['mac', 'windows', 'linux'])
  expect(table[0]?.cpus).toEqual([{ cpu: 'arm64', state: 'ready' }, { cpu: 'x86_64', state: 'untested' }])
})

test('a supported table of the wrong shape, or with a word the panel does not know, is unreadable', () => {
  for (const bad of [null, {}, [null], [{ os: 'mac' }], [{ os: 'beos', cpus: [] }], [{ os: 'mac', cpus: [{ cpu: 'riscv', state: 'ready' }] }], [{ os: 'mac', cpus: [{ cpu: 'arm64', state: 'maybe' }] }]]) {
    expect(() => parseSupported(bad), JSON.stringify(bad)).toThrow(UnreadableAnswer)
  }
})

test('waiting machines are read with their share, time and tries; an empty list is a real empty list', () => {
  expect(parsePending([])).toEqual([])
  expect(parsePending([pendingRow()])).toEqual([
    { id: 'p1', hostname: 'far-mac', os: 'mac', cpu: 'arm64', share: { cores: 4, ram_mb: 8192, disk_gb: 100 }, expiresAt: '2026-10-31T10:15:00Z', triesLeft: 5 },
  ])
})

test('a waiting machine with a missing or wrong field makes the whole answer unreadable', () => {
  const bad = [
    pendingRow({ id: 5 }), pendingRow({ hostname: undefined }), pendingRow({ os: 'dos' }), pendingRow({ tries_left: -1 }), pendingRow({ tries_left: 1.5 }),
    pendingRow({ share: { cores: 0, ram_mb: 1, disk_gb: 1 } }), pendingRow({ share: null }), pendingRow({ expires_at: 7 }),
  ]
  for (const row of bad) expect(() => parsePending([row]), JSON.stringify(row)).toThrow(UnreadableAnswer)
  expect(() => parsePending({ pending: [] })).toThrow(UnreadableAnswer)
})

test('a hostile host name stays plain text in the data', () => {
  expect(parsePending([pendingRow({ hostname: '<img src=x onerror=alert(1)>' })])[0]?.hostname).toBe('<img src=x onerror=alert(1)>')
})

test('joined machines keep the last handshake, or null when there never was one', () => {
  expect(parsePeers([peerRow(), peerRow({ name: 'b', last_handshake_secs_ago: null })]).map((peer) => peer.handshakeSecsAgo)).toEqual([12, null])
  expect(parsePeers([peerRow()])[0]).toEqual({ name: 'far-mac', address: '10.77.0.2', key: 'AbCdEfGh', os: 'mac', cpu: 'arm64', handshakeSecsAgo: 12 })
})

test('a joined machine with a wrong field is unreadable', () => {
  for (const row of [peerRow({ last_handshake_secs_ago: 'soon' }), peerRow({ last_handshake_secs_ago: -3 }), peerRow({ address: null }), peerRow({ public_key: 1 })]) {
    expect(() => parsePeers([row]), JSON.stringify(row)).toThrow(UnreadableAnswer)
  }
})

test('the made command is taken as the hub gave it', () => {
  expect(parseJoinCommand({ link: 'x', expires_at: '2026-10-31T11:00:00Z', command: 'curl -fsSL "https://h/j/x?os=mac&cpu=arm64" | sh' })).toEqual({ command: 'curl -fsSL "https://h/j/x?os=mac&cpu=arm64" | sh', expiresAt: '2026-10-31T11:00:00Z' })
  expect(() => parseJoinCommand({ link: 'x' })).toThrow(UnreadableAnswer)
  expect(() => parseJoinCommand(null)).toThrow(UnreadableAnswer)
})
