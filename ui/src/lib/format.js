// Pure helpers for showing machine data. No DOM, no network, so they are easy to test.

const SECOND = 1000
const MINUTE = 60 * SECOND
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

export function relativeTime(iso, now = Date.now()) {
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

export function formatMb(mb) {
  if (mb === null || mb === undefined) return '–'
  return mb >= 1024 ? `${trim(mb / 1024)} GB` : `${mb} MB`
}

export function formatGb(gb) {
  if (gb === null || gb === undefined) return '–'
  return gb >= 1000 ? `${trim(gb / 1000)} TB` : `${gb} GB`
}

function trim(value) {
  return value >= 100 ? String(Math.round(value)) : value.toFixed(1).replace(/\.0$/, '')
}

const OS_NAMES = { macos: 'macOS', linux: 'Linux', windows: 'Windows' }
export function osName(os) {
  return OS_NAMES[os] ?? '–'
}

const ARCH_NAMES = { arm64: 'ARM', aarch64: 'ARM', x86_64: 'x86' }
export function archName(arch) {
  return ARCH_NAMES[arch] ?? '–'
}

export function usedPercent(free, total) {
  if (!total || free === null || free === undefined) return null
  return Math.min(100, Math.max(0, Math.round(((total - free) / total) * 100)))
}

export const STATE_LABELS = { online: 'Online', busy: 'Busy', offline: 'Offline' }

export function summarize(machines) {
  const workloads = machines.reduce((sum, machine) => sum + machine.workloads.length, 0)
  return {
    machines: machines.length,
    online: machines.filter((machine) => machine.state !== 'offline').length,
    workloads,
  }
}

const NAME_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}$/
export function nameProblem(name) {
  if (!name) return 'Give the machine a name.'
  if (name.length > 63) return 'Use at most 63 characters.'
  if (!NAME_PATTERN.test(name)) return 'Use lowercase letters, numbers and dashes, starting with a letter or number.'
  return null
}

const SOURCE_LABELS = { router: 'Router', nmap: 'nmap', agent_probe: 'Agent check', arp: 'ARP table' }
const SOURCE_PROBLEMS = {
  not_configured: 'not set up',
  missing: 'not installed',
  failed: 'failed',
  unreachable: 'cannot be reached',
  outside_subnet: 'is outside the scanned network',
}

export function sourceName(source) {
  return SOURCE_LABELS[source] ?? source
}

/** A short human sentence for how one scan source went, or null when it went fine. */
export function sourceProblem(value) {
  if (value === 'ok') return null
  if (value === 'refused_401') return 'login refused (check the read-only account)'
  if (value?.startsWith('refused_')) return `refused (${value.slice('refused_'.length)})`
  return SOURCE_PROBLEMS[value] ?? 'did not run'
}

/** A machine name from a device's host name, following the same rule as the Root. Falls back to the last part of the address. */
export function suggestName(hostname, ip) {
  const cleaned = (hostname ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 63).replace(/-+$/, '')
  if (cleaned && NAME_PATTERN.test(cleaned)) return cleaned
  return `device-${(ip ?? '').split('.').pop() || 'new'}`
}

const KIND_LIMITS = { cpu: [1, 64], ramGb: [0.5, 1024], diskGb: [1, 100000] }

/** What is wrong with a new-workload form, or null. Same limits as the Root, so a bad form never leaves the page. */
export function workloadProblem(form) {
  const named = nameProblem(form.name)
  if (named) return named
  if (!['vm', 'container'].includes(form.kind)) return 'Pick VM or container.'
  for (const [field, [low, high]] of Object.entries(KIND_LIMITS)) {
    const value = Number(form[field])
    if (!Number.isFinite(value) || value < low || value > high) return `${LABELS[field]} must be between ${low} and ${high}.`
  }
  return Number.isInteger(Number(form.cpu)) && Number.isInteger(Number(form.diskGb)) ? null : 'CPU and disk must be whole numbers.'
}

const LABELS = { cpu: 'CPU', ramGb: 'RAM (GB)', diskGb: 'Disk (GB)' }

export function workloadBody(form) {
  const body = { name: form.name, kind: form.kind, cpu: Number(form.cpu), ram_mb: Math.round(Number(form.ramGb) * 1024), disk_gb: Number(form.diskGb) }
  return form.machine ? { ...body, machine: form.machine } : body
}

const COMMAND_LABELS = { create: 'Create', start: 'Start', stop: 'Stop', delete: 'Delete' }
export function commandName(type) {
  return COMMAND_LABELS[type] ?? type
}

/** One line saying how a command ended. */
export function commandOutcome(command) {
  if (command.state === 'failed') return command.result?.error ?? 'failed'
  if (command.state !== 'succeeded') return 'working…'
  if (command.result?.backup_id && command.result.backup_id !== 'none') return `backup kept: ${command.result.backup_id}`
  return 'done'
}

/** What to say about a bundle version next to the pinned one: nothing, "no chat", or "needs 0.2.0". */
export function bundleFlag(installed, pinned) {
  if (!installed) return { text: 'no chat', stale: false }
  if (!pinned || installed === pinned) return { text: `chat ${installed}`, stale: false }
  return { text: `chat ${installed}, needs ${pinned}`, stale: true }
}
