// The machines the theme pictures show, on a real Root: a Mac with VMs, a PC with a GPU, a machine with a reported problem, and one that never reported (offline).
import { createServer } from 'node:http'
import { signIn } from '../support/admin.ts'
import { enrollMachine, sendHeartbeat, type World } from '../panel/world.ts'
import type { RunningRoot } from '../support/root.ts'

export const MAC = 'mac-studio'
export const GPU_PC = 'rtx-5090'
export const SICK = 'dgx-spark'
export const OFFLINE = 'quiet-pc'

const BOTH = { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }
const GPU_FACTS = [{ vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090' }]
const PROBLEM = { code: 'bridge_blocked_by_firewall', message: 'VMs cannot get an IPv4 address: the bridge incusbr0 is not trusted.', fix: 'As root, run: metaservice-agent setup --yes' }

const vm = (id: string, name: string, state: string, cpu: number, ramMb: number, diskGb: number, address: string | null) =>
  ({ id, name, kind: 'vm', state, cpu, ram_mb: ramMb, disk_gb: diskGb, gpu_mode: 'none', address, bundle_version: state === 'running' ? '1.0.0' : null })

const facts = (os: string, arch: string, cores: number, ramMb: number, diskGb: number, gpu: object[], problems: object[]) =>
  ({ os, arch, cpu_cores: cores, ram_total_mb: ramMb, disk_total_gb: diskGb, free_ram_mb: Math.round(ramMb * 0.55), free_disk_gb: Math.round(diskGb * 0.7), gpu, capabilities: BOTH, problems })

const beat = (factsBody: object, workloads: object[]) => ({ facts: factsBody, workloads, bundle_version: '1.0.0' })

const HEARTBEATS: ReadonlyArray<readonly [string, object]> = [
  [MAC, beat(facts('macos', 'arm64', 14, 36864, 494, [], []), [vm('w1', 'build-box', 'running', 4, 8192, 60, '10.0.0.21'), vm('w2', 'chat-demo', 'running', 2, 4096, 30, '10.0.0.22'), vm('w3', 'old-test', 'stopped', 2, 2048, 20, null)])],
  [GPU_PC, beat(facts('linux', 'x86_64', 32, 65536, 2000, GPU_FACTS, []), [vm('w4', 'trainer', 'running', 8, 16384, 200, '10.0.1.5')])],
  [SICK, beat(facts('linux', 'aarch64', 20, 131072, 3800, [], [PROBLEM]), [])],
]

/** A world around a Root that was started with its own options (the Add machine check needs the remote ones). The AI provider is not used, so the one here never listens. */
export const worldAround = (root: RunningRoot): World => ({ provider: { failing: false, base: '', server: createServer() }, root, session: null })

/** Signs in through the API, makes the machines and sends their first heartbeats. The offline machine is enrolled and then stays silent. */
export async function seedFleet(world: World): Promise<void> {
  const session = await signIn(world.root.base)
  world.session = session
  for (const [name, body] of HEARTBEATS) await sendHeartbeat(world, await enrollMachine(world, session, name), body)
  await enrollMachine(world, session, OFFLINE)
}

