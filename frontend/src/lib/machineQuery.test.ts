import { expect, test } from 'bun:test'
import { parseQuery, queryMachines } from './machineQuery.ts'
import type { Machine } from './types.ts'

const mac = (id: string, over: Partial<Machine> = {}): Machine => ({
  id, name: id, state: 'online', os: 'macos', arch: 'arm64', gpu: [], problems: [], workloads: [], ip: '192.168.0.10', ...over,
})

const fleet = [
  mac('mac-studio', { ip: '192.168.0.10' }),
  mac('fedora', { os: 'linux', ip: '10.77.0.2' }),
  mac('mac-mini-2', { ip: '202.51.196.202', state: 'offline' }),
  mac('dgx-spark', { os: 'linux', ip: '192.168.0.30' }),
]

test('empty query returns everything', () => {
  expect(queryMachines(fleet, '')).toHaveLength(4)
  expect(queryMachines(fleet, '   ')).toHaveLength(4)
})

test('plain substring matches name, os, arch and ip', () => {
  expect(queryMachines(fleet, 'fedora')).toHaveLength(1)
  expect(queryMachines(fleet, 'linux')).toHaveLength(2)
  expect(queryMachines(fleet, '202.51')).toHaveLength(1)
})

test('multiple words are AND-ed', () => {
  expect(queryMachines(fleet, 'linux 192.168')).toHaveLength(1)
  expect(queryMachines(fleet, 'linux 202.51')).toHaveLength(0)
})

test('os: state: and ip: prefix filters', () => {
  expect(queryMachines(fleet, 'os:linux')).toHaveLength(2)
  expect(queryMachines(fleet, 'state:offline')).toHaveLength(1)
  expect(queryMachines(fleet, 'ip:10.77')).toHaveLength(1)
  expect(queryMachines(fleet, 'os:macos state:online')).toHaveLength(1)
})

test('prefix filters combine with plain terms', () => {
  expect(queryMachines(fleet, 'os:linux dgx')).toHaveLength(1)
  expect(queryMachines(fleet, 'os:linux fedora')).toHaveLength(1)
  expect(queryMachines(fleet, 'os:linux dgx fedora')).toHaveLength(0)
})

test('parseQuery splits prefixes from plain terms', () => {
  const p = parseQuery('os:linux state:online ip:10.77 plainword')
  expect(p).toEqual({ terms: ['plainword'], os: 'linux', state: 'online', ip: '10.77' })
})
