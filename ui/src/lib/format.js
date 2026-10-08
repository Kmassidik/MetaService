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
