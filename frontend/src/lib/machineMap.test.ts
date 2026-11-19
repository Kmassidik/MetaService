import { expect, test } from 'bun:test'
import { edgeKindFor, iconFor, layout, stateFor, subtitleFor } from './machineMap.ts'
import type { Machine } from './types.ts'

const mac = (id: string, over: Partial<Machine> = {}): Machine => ({
  id, name: id, state: 'online', os: 'macos', arch: 'arm64', gpu: [], problems: [], workloads: [], ...over,
})

test('each machine gets its own icon and the cloud is the fallback', () => {
  expect(iconFor(mac('fedora'))).toBe('fedora')
  expect(iconFor(mac('dgx-spark'))).toBe('dgx')
  expect(iconFor(mac('rtx5090'))).toBe('rtx5090')
  expect(iconFor(mac('mac-studio'))).toBe('macstudio')
  expect(iconFor(mac('mac-mini-2'))).toBe('macmini2')
  expect(iconFor(mac('unknown-box'))).toBe('cloud')
})

test('subtitle shows mesh for 10.77, the plain address otherwise, offline when no address', () => {
  expect(subtitleFor(mac('fedora', { ip: '10.77.0.2' }))).toBe('mesh · 10.77.0.2')
  expect(subtitleFor(mac('dgx', { ip: '192.168.0.30' }))).toBe('192.168.0.30')
  expect(subtitleFor(mac('x', { state: 'offline' }))).toBe('offline')
})

test('state: offline beats needs-setup, needs-setup beats online', () => {
  expect(stateFor(mac('x', { state: 'offline', problems: [{ code: 'x', message: 'x', fix: 'x' }] }))).toBe('offline')
  expect(stateFor(mac('x', { problems: [{ code: 'x', message: 'x', fix: 'x' }] }))).toBe('setup')
  expect(stateFor(mac('x'))).toBe('online')
})

test('edge kind: mesh for 10.77, public for 202., ssh for the office LAN', () => {
  expect(edgeKindFor(mac('fedora', { ip: '10.77.0.2' }))).toBe('mesh')
  expect(edgeKindFor(mac('mac-mini-2', { ip: '202.51.196.202' }))).toBe('public')
  expect(edgeKindFor(mac('dgx', { ip: '192.168.0.30' }))).toBe('ssh')
})

test('layout puts the hub at the centre and the others in the preset slots, with one edge each', () => {
  const machines = [mac('fedora', { ip: '10.77.0.2' }), mac('dgx-spark', { ip: '192.168.0.30' })]
  const { nodes, edges } = layout(machines, 'macminiruvio')
  const hub = nodes.find((n) => n.id === '__hub__')
  expect(hub).toBeDefined()
  expect(hub!.x).toBe(480)
  expect(hub!.y).toBe(285)
  expect(hub!.icon).toBe('hub')
  expect(nodes).toHaveLength(3)
  expect(edges).toHaveLength(2)
  expect(edges[0]!.kind).toBe('mesh')
  expect(edges[1]!.kind).toBe('ssh')
})

test('the hub machine itself is excluded from the satellite nodes', () => {
  const { nodes } = layout([mac('macminiruvio'), mac('fedora')], 'macminiruvio')
  expect(nodes.filter((n) => n.machineId === 'macminiruvio')).toHaveLength(1)
  expect(nodes[0]!.id).toBe('__hub__')
})
