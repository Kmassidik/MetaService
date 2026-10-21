// The machines the VMs pages are tested against, besides the two the panel test seeds: one that never reported (so it is offline), one that runs containers only,
// and one whose reported problem is hostile text (the Create VM page writes problems out under the dropdown, and must show them as text).
import type { Session } from '../support/admin.ts'
import { XSS, enrollMachine, sendHeartbeat, type World } from '../panel/world.ts'

export const OFFLINE_MACHINE = 'quiet-pc'
export const CONTAINER_MACHINE = 'box-only'
export const SICK_MACHINE = 'sick-box'
export const CONTAINER_VM = 'ct-box'

const FACTS = { os: 'linux', arch: 'aarch64', cpu_cores: 8, ram_total_mb: 16384, disk_total_gb: 500, free_ram_mb: 10000, free_disk_gb: 400, gpu: [] }
const BOTH_KINDS = { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }
const CONTAINERS_ONLY = { vm: false, container: true, gpu_in_vm: false, gpu_in_container: false }
const CONTAINER = { id: 'ct-1', name: CONTAINER_VM, kind: 'container', state: 'running', cpu: 1, ram_mb: 512, disk_gb: 5, gpu_mode: 'none', address: null, bundle_version: null }
const HOSTILE_PROBLEM = { code: 'bridge_blocked_by_firewall', message: XSS, fix: 'As root, run: metaservice-agent setup --yes' }

/** Enrolls the offline machine (it never sends a heartbeat), the containers-only machine with one container, and the machine with a hostile problem text. */
export async function addExtraMachines(world: World, session: Session): Promise<void> {
  await enrollMachine(world, session, OFFLINE_MACHINE)
  const containers = await enrollMachine(world, session, CONTAINER_MACHINE)
  await sendHeartbeat(world, containers, { facts: { ...FACTS, capabilities: CONTAINERS_ONLY, problems: [] }, workloads: [CONTAINER], bundle_version: null })
  const sick = await enrollMachine(world, session, SICK_MACHINE)
  await sendHeartbeat(world, sick, { facts: { ...FACTS, capabilities: BOTH_KINDS, problems: [HOSTILE_PROBLEM] }, workloads: [], bundle_version: null })
}
