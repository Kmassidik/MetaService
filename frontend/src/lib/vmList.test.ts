import { test, expect } from 'bun:test'
import { machine, workload } from './testing.ts'
import { filterRows, vmFilterFromRoute, vmRows, vmsHeader, vmTone } from './vmList.ts'

const fleet = [
  machine({ id: 'zeta', name: 'zeta', workloads: [workload({ id: 'w-2', name: 'beta' }), workload({ id: 'w-1', name: 'alpha', kind: 'container', state: 'stopped' })] }),
  machine({ id: 'alpha-box', name: 'Alpha box', state: 'offline', workloads: [workload({ id: 'w-9', name: 'old', cpu: 4, ram_mb: 8192, disk_gb: 100 })] }),
  machine({ id: 'empty', name: 'empty' }),
]

test('every VM of every machine is one row, sorted by machine name then VM name', () => {
  expect(vmRows(fleet).map((row) => [row.machineName, row.name])).toEqual([['Alpha box', 'old'], ['zeta', 'alpha'], ['zeta', 'beta']])
})

test('a row carries what the table shows, and its machine\'s state', () => {
  const row = vmRows(fleet)[0]
  expect(row).toMatchObject({ machineId: 'alpha-box', machineState: 'offline', machineOs: 'macos', id: 'w-9', kind: 'vm', state: 'running', cpu: 4, ramMb: 8192, diskGb: 100 })
})

test('a row carries the reason a stopped VM gave, read again, and whether it runs without systemd', () => {
  const reason = { exit_code: 255, log_tail: 'Exiting PID 1...' }
  const rows = vmRows([machine({ workloads: [workload({ id: 'a', name: 'a', state: 'stopped', stopped_reason: reason, init_mode: 'plain' }), workload({ id: 'b', name: 'b' }), workload({ id: 'c', name: 'c', stopped_reason: { nonsense: true } })] })])
  expect(rows.map((row) => [row.id, row.note, row.plain])).toEqual([['a', { kind: 'reason', reason }, true], ['b', null, false], ['c', null, false]])
})

test('sorting ignores upper and lower case and does not change the machines it was given', () => {
  const mixed = [machine({ id: 'b', name: 'b', workloads: [workload({ name: 'Zed' }), workload({ id: 'w2', name: 'apple' })] })]
  expect(vmRows(mixed).map((row) => row.name)).toEqual(['apple', 'Zed'])
  expect(mixed[0]?.workloads.map((entry) => entry.name)).toEqual(['Zed', 'apple'])
})

test('filtering by a machine keeps only its VMs; no machine keeps all', () => {
  const rows = vmRows(fleet)
  expect(filterRows(rows, 'zeta').map((row) => row.name)).toEqual(['alpha', 'beta'])
  expect(filterRows(rows, null)).toHaveLength(3)
  expect(filterRows(rows, 'empty')).toEqual([])
})

test('the filter in the address is used only when that machine is on the list; an unknown or invalid id means all machines', () => {
  expect(vmFilterFromRoute('/vms?machine=zeta', fleet)).toBe('zeta')
  for (const route of ['/vms', '/vms?machine=gone', '/vms?machine=Bad Name', '/vms?machine=', '/machines?machine=zeta']) expect(vmFilterFromRoute(route, fleet), route).toBeNull()
})

test('the header counts VMs and the machines they are on', () => {
  const rows = vmRows(fleet)
  expect(vmsHeader(rows)).toBe('3 VMs on 2 machines')
  expect(vmsHeader(filterRows(rows, 'zeta'))).toBe('2 VMs on 1 machine')
  expect(vmsHeader(filterRows(rows, 'alpha-box'))).toBe('1 VM on 1 machine')
  expect(vmsHeader([])).toBe('0 VMs')
})

test('a VM state gets the colour the rest of the panel gives it', () => {
  expect(['running', 'creating', 'starting', 'provisioning', 'stopped', 'weird'].map(vmTone)).toEqual(['online', 'busy', 'busy', 'busy', '', ''])
})
