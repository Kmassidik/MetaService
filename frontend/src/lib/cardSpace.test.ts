import { expect, test } from 'bun:test'
import { liveDisk, liveMemory, vmRoom } from './cardSpace.ts'
import type { MachineStats } from './types.ts'

const stats = (memory: Partial<MachineStats['memory']>, disks: MachineStats['disks'] = []): MachineStats =>
  ({ memory: { total_bytes: 16 * 1024 ** 3, used_bytes: 4 * 1024 ** 3, cached_bytes: 6 * 1024 ** 3, free_bytes: 1024 ** 3, swap_total_bytes: 0, swap_used_bytes: 0, ...memory }, disks }) as MachineStats

test('memory in use is what programs hold; caches count as free', () => {
  expect(liveMemory(stats({}))).toEqual({ free: 12 * 1024, total: 16 * 1024 })
  expect(liveMemory(null)).toBeNull()
  expect(liveMemory(stats({ total_bytes: 0 }))).toBeNull()
})

test('the disk is the root mount, or the biggest one without a root, in GiB like the detail page', () => {
  const disks = [
    { mount: '/data', name: 'b', fs: 'ext4', total_bytes: 2 * 1024 ** 3 * 1000, used_bytes: 1024 ** 3 * 1000, free_bytes: 1024 ** 3 * 1000 },
    { mount: '/', name: 'a', fs: 'ext4', total_bytes: 500 * 1024 ** 3, used_bytes: 100 * 1024 ** 3, free_bytes: 400 * 1024 ** 3 },
  ]
  expect(liveDisk(stats({}, disks))).toEqual({ free: 400, total: 500 })
  expect(liveDisk(stats({}, disks.slice(0, 1)))).toEqual({ free: 1000, total: 2000 })
  expect(liveDisk(stats({}, []))).toBeNull()
})

test('the VM room line says what is left for VMs, and is left out when the machine does not say', () => {
  expect(vmRoom({ free_ram_mb: 3789, free_disk_gb: 68 })).toBe('Room for VMs: 3.7 GB memory · 68 GB disk')
  expect(vmRoom({ free_ram_mb: null, free_disk_gb: 68 })).toBeNull()
})
