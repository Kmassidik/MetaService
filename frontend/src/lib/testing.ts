// Complete example objects for the tests, so each test only says what it is about.
import type { Command, InstallForm, Machine, Workload } from './types.ts'

export const workload = (extra: Partial<Workload> = {}): Workload => ({ id: 'w1', name: 'vm', kind: 'vm', state: 'running', cpu: 2, ram_mb: 4096, disk_gb: 40, ...extra })

export const machine = (extra: Partial<Machine> = {}): Machine => ({ id: 'm', name: 'm', state: 'online', os: 'macos', arch: 'arm64', gpu: [], workloads: [], ...extra })

export const command = (extra: Partial<Command> = {}): Command => ({ id: 'c1', type: 'create', machine: 'm', state: 'running', created_at: '2026-01-01T00:00:00Z', params: {}, ...extra })

export const installForm = (extra: Partial<InstallForm> = {}): InstallForm => ({
  name: '', profile: 'custom', labels: '', notes: '', chat: false, ramReserveMb: '', diskReserveGb: '', ramAllowanceMb: '', diskAllowanceGb: '', allowGpu: true,
  vmCpu: '', vmRamMb: '', vmDiskGb: '', vmImage: '', vmMaxRunning: '', subdomain: '', publicChat: false, aiModel: '', ...extra,
})
