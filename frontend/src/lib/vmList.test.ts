import { test, expect } from 'bun:test'
import { machine, workload } from './testing.ts'
import { filterRows, findVm, vmFilterFromRoute, vmRows, vmsHeader, vmTone } from './vmList.ts'

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
  expect(row).toMatchObject({ machineId: 'alpha-box', machineState: 'offline', id: 'w-9', kind: 'vm', state: 'running', cpu: 4, ramMb: 8192, diskGb: 100 })
})

test('a row carries the reason a stopped VM gave, read again, and whether it runs without systemd', () => {
  const reason = { exit_code: 255, log_tail: 'Exiting PID 1...' }
  const rows = vmRows([machine({ workloads: [workload({ id: 'a', name: 'a', state: 'stopped', stopped_reason: reason, init_mode: 'plain' }), workload({ id: 'b', name: 'b' }), workload({ id: 'c', name: 'c', stopped_reason: { nonsense: true } })] })])
  expect(rows.map((row) => [row.id, row.note, row.plain])).toEqual([['a', { kind: 'reason', reason }, true], ['b', null, false], ['c', null, false]])
})

test('a row carries the chip of the app being installed in the VM, or none', () => {
  const rows = vmRows([machine({ workloads: [workload({ id: 'a', name: 'a', app: { name: 'openclaw', state: 'installing', message: null } }), workload({ id: 'b', name: 'b', app: null }), workload({ id: 'c', name: 'c' })] })])
  expect(rows.map((row) => [row.id, row.app?.text ?? null])).toEqual([['a', 'Installing OpenClaw…'], ['b', null], ['c', null]])
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

test('a row finds its machine and VM again, and nothing when they are gone', () => {
  const found = findVm(fleet, { machineId: 'zeta', id: 'w-1' })
  expect(found?.machine.id).toBe('zeta')
  expect(found?.workload.name).toBe('alpha')
  expect(findVm(fleet, { machineId: 'zeta', id: 'w-404' })).toBeNull()
  expect(findVm(fleet, { machineId: 'gone', id: 'w-1' })).toBeNull()
})

test('a VM with a GPU memory limit has it in its row, and one without has none', () => {
  const rows = vmRows([machine({ id: 'g', name: 'g', workloads: [workload({ id: 'a', name: 'a', gpu_memory_gb: 4 }), workload({ id: 'b', name: 'b', gpu_memory_gb: null }), workload({ id: 'c', name: 'c', gpu_memory_gb: 'four' }), workload({ id: 'd', name: 'd' })] })])
  expect(rows.map((row) => row.gpuLimitGb)).toEqual([4, null, null, null])
})
