// Pure helpers for showing machine data. No DOM, no network, so they are easy to test.
import { imageBundle } from './images.ts'
import type { Command, WorkloadForm } from './types.ts'

const SECOND = 1000
const MINUTE = 60 * SECOND
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

export function relativeTime(iso: string | null | undefined, now: number = Date.now()): string {
  if (!iso) return 'never'
  const then = Date.parse(iso)
  if (Number.isNaN(then)) return 'unknown'
  const age = Math.max(0, now - then)
  if (age < 5 * SECOND) return 'just now'
  if (age < MINUTE) return `${Math.floor(age / SECOND)}s ago`
  if (age < HOUR) return `${Math.floor(age / MINUTE)}m ago`
  if (age < DAY) return `${Math.floor(age / HOUR)}h ago`
  return `${Math.floor(age / DAY)}d ago`
}

export function formatMb(mb: number | null | undefined): string {
  if (mb === null || mb === undefined) return '–'
  return mb >= 1024 ? `${trim(mb / 1024)} GB` : `${mb} MB`
}

export function formatGb(gb: number | null | undefined): string {
  if (gb === null || gb === undefined) return '–'
  return gb >= 1000 ? `${trim(gb / 1000)} TB` : `${gb} GB`
}

function trim(value: number): string {
  return value >= 100 ? String(Math.round(value)) : value.toFixed(1).replace(/\.0$/, '')
}

const OS_NAMES: Record<string, string> = { macos: 'macOS', linux: 'Linux', windows: 'Windows' }
export function osName(os: string | null | undefined): string {
  return (os && OS_NAMES[os]) || '–'
}

const ARCH_NAMES: Record<string, string> = { arm64: 'ARM', aarch64: 'ARM', x86_64: 'x86' }
export function archName(arch: string | null | undefined): string {
  return (arch && ARCH_NAMES[arch]) || '–'
}

export function usedPercent(free: number | null | undefined, total: number | null | undefined): number | null {
  if (!total || free === null || free === undefined) return null
  return Math.min(100, Math.max(0, Math.round(((total - free) / total) * 100)))
}

export const STATE_LABELS: Record<string, string> = { online: 'Online', busy: 'Busy', offline: 'Offline' }

const NAME_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}$/
export function nameProblem(name: string): string | null {
  if (!name) return 'Give the machine a name.'
  if (name.length > 63) return 'Use at most 63 characters.'
  if (!NAME_PATTERN.test(name)) return 'Use lowercase letters, numbers and dashes, starting with a letter or number.'
  return null
}

const SOURCE_LABELS: Record<string, string> = { router: 'Router', nmap: 'Network scan', agent_probe: 'Agent check', arp: 'Network' }
const SOURCE_PROBLEMS: Record<string, string> = {
  not_configured: 'not set up',
  missing: 'not installed',
  failed: 'failed',
  unreachable: 'cannot be reached',
  outside_subnet: 'is outside the scanned network',
}

export function sourceName(source: string): string {
  return SOURCE_LABELS[source] ?? source
}

/** A short human sentence for how one scan source went, or null when it went fine. */
export function sourceProblem(value: string | null | undefined): string | null {
  if (value === 'ok') return null
  if (value === 'refused_401') return 'login refused (check the read-only account)'
  if (value?.startsWith('refused_')) return `refused (${value.slice('refused_'.length)})`
  return (value && SOURCE_PROBLEMS[value]) || 'did not run'
}

type LimitedField = 'cpu' | 'ramGb' | 'diskGb'
const KIND_LIMITS: Record<LimitedField, [number, number]> = { cpu: [1, 64], ramGb: [0.5, 1024], diskGb: [1, 100000] }

/** What is wrong with a new-workload form, or null. Same limits as the Root, so a bad form never leaves the page. */
export function workloadProblem(form: WorkloadForm): string | null {
  const named = nameProblem(form.name)
  if (named) return named
  if (!['vm', 'container'].includes(form.kind)) return 'Pick VM or container.'
  for (const [field, [low, high]] of Object.entries(KIND_LIMITS) as [LimitedField, [number, number]][]) {
    const value = Number(form[field])
    if (!Number.isFinite(value) || value < low || value > high) return `${LABELS[field]} must be between ${low} and ${high}.`
  }
  return Number.isInteger(Number(form.cpu)) && Number.isInteger(Number(form.diskGb)) ? null : 'CPU and disk must be whole numbers.'
}

const LABELS: Record<LimitedField, string> = { cpu: 'CPU', ramGb: 'RAM (GB)', diskGb: 'Disk (GB)' }

export function workloadBody(form: WorkloadForm): Record<string, unknown> {
  const body = { name: form.name, kind: form.kind, cpu: Number(form.cpu), ram_mb: Math.round(Number(form.ramGb) * 1024), disk_gb: Number(form.diskGb) }
  const withGpu = form.gpuMode === 'container' && form.kind === 'container' ? { ...body, gpu_mode: 'container' } : body
  const bundle = imageBundle(form.bundle)
  const withImage = bundle === undefined ? withGpu : { ...withGpu, bundle }
  return form.machine ? { ...withImage, machine: form.machine } : withImage
}

const COMMAND_LABELS: Record<string, string> = { create: 'Create', start: 'Start', stop: 'Stop', delete: 'Delete' }
export function commandName(type: string): string {
  return COMMAND_LABELS[type] ?? type
}

/** One line saying how a command ended. */
export function commandOutcome(command: Command): string {
  if (command.state === 'failed') return command.result?.error ?? 'failed'
  if (command.state !== 'succeeded') return 'working…'
  if (command.result?.backup_id && command.result.backup_id !== 'none') return `backup kept: ${command.result.backup_id}`
  return 'done'
}

/** What to say about a bundle version next to the pinned one: nothing, "no chat", or "needs 0.2.0". */
export function bundleFlag(installed: string | null | undefined, pinned: string | null | undefined): { text: string; stale: boolean } {
  if (!installed) return { text: 'no chat', stale: false }
  if (!pinned || installed === pinned) return { text: `chat ${installed}`, stale: false }
  return { text: `chat ${installed}, needs ${pinned}`, stale: true }
}

export const PROFILES = [
  { id: 'apple-silicon-mac', label: 'Apple Silicon Mac' },
  { id: 'linux-x86', label: 'Linux PC (x86)' },
  { id: 'linux-arm', label: 'Linux (ARM)' },
  { id: 'gpu-box', label: 'GPU box (DGX)' },
  { id: 'custom', label: 'Other' },
]

export const profileLabel = (id: string | null | undefined) => PROFILES.find((profile) => profile.id === id)?.label ?? 'Other'

