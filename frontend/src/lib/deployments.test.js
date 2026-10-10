import test from 'node:test'
import assert from 'node:assert/strict'
import { hostFor, vmServers } from './deployments.js'

const machine = {
  name: 'mac-mini', os: 'macos', arch: 'arm64', ram_total_mb: 16384, cpu_cores: 10, disk_total_gb: 494, free_disk_gb: 263, settings: { ram_reserve_mb: 4096 },
  workloads: [{ id: 'w1', name: 'build-box', state: 'running', ram_mb: 4096, cpu: 2, disk_gb: 40 }, { id: 'w2', name: 'old', state: 'stopped', ram_mb: 2048, cpu: 1, disk_gb: 20 }, { id: 'w3', name: 'new', state: 'creating', ram_mb: 1024, cpu: 1, disk_gb: 10 }],
}

test('VMs become servers the building, cards and table share', () => {
  const servers = vmServers(machine)
  assert.deepEqual(servers.map((server) => [server.display, server.status, server.cls, server.mem_mb]), [['build-box', 'running', 'run', 4096], ['old', 'stopped', '', 2048], ['new', 'creating', 'prog', 1024]])
  assert.deepEqual(vmServers({ workloads: [] }), [])
})

test('the machine is the host: its memory, cores, disk and what its VMs take of the disk', () => {
  assert.deepEqual(hostFor(machine), { chip: 'mac-mini', apple: true, ram_total_mb: 16384, ram_reserve_mb: 4096, cpu_total: 10, disk_total_gb: 494, disk_free_gb: 263, disk_alloc_gb: 70 })
  const linux = hostFor({ name: 'dgx', os: 'linux', arch: 'x86_64', workloads: [] })
  assert.equal(linux.apple, false)
  assert.deepEqual([linux.ram_total_mb, linux.disk_alloc_gb, linux.ram_reserve_mb], [0, 0, undefined])
})
