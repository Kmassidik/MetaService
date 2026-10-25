// What the machine page's Environment tab says about a machine: software, Ruvio, and what it can run. Pure functions, no DOM, no network.
import { cpuText, drivesText, gpuDetailText, memorySharedWithGpu, readHardware, SHARED_WITH_GPU } from './hardware.ts'
import { archName, formatGb, formatMb, osName, relativeTime } from './format.ts'
import { connectionText } from './remote.ts'
import type { Capabilities, Engine, Gpu, Machine, RemoteMachineInfo, Ruvio } from './types.ts'

/** What a value shows when the helper did not report it. Never a guess. */
export const NOT_REPORTED = 'not reported'
export const NO_CHAT_BUILT = 'no chat is built on the parent'
export const CHAT_NOT_PINNED = 'several chats are built and none is chosen: choose one in Settings'
const MACHINE_OFFLINE = 'the machine is offline'
const NOT_REPORTED_YET = 'the machine has not reported yet'

export const reported = (value: string | number | null | undefined): string => (value === null || value === undefined || value === '' ? NOT_REPORTED : String(value))

const VERSION = /^\d+(\.\d+)*$/

function versionParts(version: string): number[] | null {
  return VERSION.test(version) ? version.split('.').map(Number) : null
}

/** Negative when `a` is behind `b`, zero when equal, positive when ahead; null when either is not a dotted number. */
export function compareVersions(a: string, b: string): number | null {
  const left = versionParts(a)
  const right = versionParts(b)
  if (!left || !right) return null
  const length = Math.max(left.length, right.length)
  for (let index = 0; index < length; index++) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0)
    if (difference !== 0) return difference
  }
  return 0
}

/** The highest helper version any machine reports: the nearest thing to "the parent's" version the parent's answers give. */
export function newestVersion(versions: ReadonlyArray<string | null | undefined>): string | null {
  let newest: string | null = null
  for (const version of versions) {
    if (!version || !VERSION.test(version)) continue
    if (newest === null || (compareVersions(version, newest) ?? 0) > 0) newest = version
  }
  return newest
}

/** True when this helper is behind the newest one. An unreadable version is never called old. */
export function helperIsOld(version: string | null | undefined, newest: string | null): boolean {
  if (!version || !newest) return false
  return (compareVersions(version, newest) ?? 0) < 0
}

const ENGINE_NAMES: Record<string, string> = { apple: 'Apple container', incus: 'Incus' }

/** For example "Apple container 1.5.0, ready". */
export function engineText(engine: Engine | null | undefined): string {
  if (!engine) return NOT_REPORTED
  const name = ENGINE_NAMES[engine.name] ?? engine.name
  return `${[name, engine.version].filter(Boolean).join(' ')}, ${engine.ready ? 'ready' : 'not ready'}`
}

/** "Can run: VMs and containers · GPU in a VM: no · GPU in a container: no", or the plain fact that nothing was reported. */
export function canRunText(capabilities: Capabilities | undefined): string {
  if (!capabilities) return `Can run: ${NOT_REPORTED}`
  const kinds = [capabilities.vm && 'VMs', capabilities.container && 'containers'].filter(Boolean).join(' and ')
  const yesNo = (flag: boolean) => (flag ? 'yes' : 'no')
  return `Can run: ${kinds || 'nothing yet'} · GPU in a VM: ${yesNo(capabilities.gpu_in_vm)} · GPU in a container: ${yesNo(capabilities.gpu_in_container)}`
}

export const gpuText = (gpu: Gpu[]): string => (gpu.length ? gpu.map(gpuDetailText).join(', ') : 'none')

/**
 * What the machine is, one plain row each: the facts the old Overview tab showed, and the spec a newer helper gives (the computer, each kind of CPU core,
 * the drives, the GPU's details). A row the helper has nothing for is left out rather than guessed.
 */
export function factRows(machine: Machine, now: number): SoftwareRow[] {
  const row = (label: string, value: string): SoftwareRow => ({ label, value, old: false })
  const system = machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch)
  const hardware = readHardware(machine.hardware)
  const drives = drivesText(hardware)
  const sharedMemory = memorySharedWithGpu(machine) ? ` · ${SHARED_WITH_GPU}` : ''
  return [
    row('Machine ID', machine.id),
    row('Status', machine.state),
    row('Address', machine.ip ?? 'unknown'),
    row('System', `${osName(machine.os)} · ${system}`),
    ...(hardware?.system ? [row('Computer', hardware.system)] : []),
    row('CPU', cpuText(machine)),
    row('Memory', `${formatMb(machine.free_ram_mb)} free of ${formatMb(machine.ram_total_mb)}${sharedMemory}`),
    row('Disk', `${formatGb(machine.free_disk_gb)} free of ${formatGb(machine.disk_total_gb)}`),
    ...(drives ? [row('Drives', drives)] : []),
    row('GPU', gpuText(machine.gpu)),
    row('Last seen', relativeTime(machine.last_seen, now)),
  ]
}

/** The tunnel the parent keeps to the helper, in words. A machine the parent did not install over SSH has none to report. */
export const tunnelText = (remote: RemoteMachineInfo | null, now: number): string => (remote ? connectionText(remote, now) : NOT_REPORTED)

export interface SoftwareRow {
  label: string
  value: string
  /** True when the value is a helper version that is behind the newest. */
  old: boolean
}

export function softwareRows(machine: Machine, remote: RemoteMachineInfo | null, newest: string | null, now: number): SoftwareRow[] {
  const row = (label: string, value: string, old = false): SoftwareRow => ({ label, value, old })
  return [
    row('Helper version', reported(machine.agent_version), helperIsOld(machine.agent_version, newest)),
    row('Engine', engineText(machine.engine)),
    row('Helper folder', reported(machine.box)),
    row('Helper port', reported(machine.agent_port)),
    row('Tunnel', tunnelText(remote, now)),
  ]
}

/** How the Ruvio switch looks and what it may do. */
export interface RuvioView {
  /** The switch shows on. */
  on: boolean
  /** The switch can be pressed. */
  canToggle: boolean
  /** A command is going: the switch waits. */
  busy: boolean
  /** One line about the state. */
  status: string
  /** Why the switch cannot be pressed, when it cannot. */
  reason: string | null
  canOpen: boolean
  /** Another version than the chosen one runs, so it can be brought up to date. */
  canUpdate: boolean
}

const idle: RuvioView = { on: false, canToggle: false, busy: false, status: NOT_REPORTED, reason: null, canOpen: false, canUpdate: false }

function viewOfState(ruvio: Ruvio, chatsBuilt: number): RuvioView {
  switch (ruvio.state) {
    case 'installing': return { ...idle, on: true, busy: true, status: 'turning on…' }
    case 'removing': return { ...idle, busy: true, status: 'turning off…' }
    case 'unavailable': return { ...idle, status: 'off', reason: chatsBuilt === 0 ? NO_CHAT_BUILT : CHAT_NOT_PINNED }
    case 'off': return { ...idle, canToggle: true, status: 'off' }
    case 'on': return { ...idle, on: true, canToggle: true, canOpen: true, status: 'on' }
    case 'outdated': return { ...idle, on: true, canToggle: true, canOpen: true, canUpdate: true, status: 'on, old version' }
  }
}

/** `chatsBuilt` is how many chat versions the parent has; `online` is whether the machine answers. A machine that is offline cannot be switched. */
export function ruvioView(ruvio: Ruvio | null | undefined, chatsBuilt: number, online: boolean): RuvioView {
  if (!ruvio) return { ...idle, reason: NOT_REPORTED_YET }
  const view = viewOfState(ruvio, chatsBuilt)
  if (online || !view.canToggle) return view
  return { ...view, canToggle: false, canOpen: false, canUpdate: false, reason: MACHINE_OFFLINE }
}
