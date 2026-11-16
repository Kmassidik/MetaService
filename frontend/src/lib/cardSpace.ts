// The memory and disk bars of a machine card. They show what the computer is really using (the live reading), so green means it has room and amber or red means it is filling up.
// Before the first reading, or when there is none, they fall back to the machine record's numbers, which are the room left for VMs (see vmRoom), not the computer's own use.
import { formatGb, formatMb } from './format.ts'
import type { Machine, MachineStats } from './types.ts'

export interface Space {
  free: number
  total: number
}

const BYTES_PER_MB = 1024 * 1024
const BYTES_PER_GB = 1_000_000_000
const ROOT_MOUNT = '/'

/** Memory in MB: what is not in use, caches included (a cache is given back the moment a program asks for the memory). */
export function liveMemory(stats: MachineStats | null): Space | null {
  const memory = stats?.memory
  if (!memory || memory.total_bytes <= 0) return null
  return { free: Math.max(0, Math.round((memory.total_bytes - memory.used_bytes) / BYTES_PER_MB)), total: Math.round(memory.total_bytes / BYTES_PER_MB) }
}

/** The system disk in GB: the root mount, or the biggest disk when there is no root. */
export function liveDisk(stats: MachineStats | null): Space | null {
  const disks = stats?.disks ?? []
  const disk = disks.find((candidate) => candidate.mount === ROOT_MOUNT) ?? [...disks].sort((left, right) => right.total_bytes - left.total_bytes)[0]
  if (!disk || disk.total_bytes <= 0) return null
  return { free: Math.max(0, Math.round(disk.free_bytes / BYTES_PER_GB)), total: Math.round(disk.total_bytes / BYTES_PER_GB) }
}

/** What the machine can still give to new VMs: its share, minus the host's own reserve, minus what VMs already hold. Null when the machine does not say. */
export function vmRoom(machine: Pick<Machine, 'free_ram_mb' | 'free_disk_gb'>): string | null {
  if (machine.free_ram_mb === null || machine.free_ram_mb === undefined || machine.free_disk_gb === null || machine.free_disk_gb === undefined) return null
  return `Room for VMs: ${formatMb(machine.free_ram_mb)} memory · ${formatGb(machine.free_disk_gb)} disk`
}
