// The four machines of the Security test, each with the report its helper would send (the `security` object of the machine). The numbers follow the real ones:
// about 96,000 failed logins in 17 days from 24 addresses, the same few user names, key logins from a few addresses. This is fake data; no helper sends it yet.
import type { Json } from '../support/json.ts'

export const HEALTHY = 'ubuntu-box'
export const WARNING = 'gpu-pc'
export const MAC = 'mac-studio'
export const OLD_HELPER = 'dgx-old'
/** What a bot calls itself in the warning machine's list: it must show as text and run nothing. */
export const HOSTILE_NAME = '<script>window.__pwned=1</script>'
export const HOSTILE_IMG = '<img src=x onerror="window.__pwned=1">'

const HOUR_MS = 3_600_000
const DAY_MS = 24 * HOUR_MS
const DAYS_REPORTED = 17
const TOTAL_FAILED = 96_000
const BLOCKED_ADDRESSES = 24

const ago = (ms: number): string => new Date(Date.now() - ms).toISOString()
const later = (ms: number): string => new Date(Date.now() + ms).toISOString()

/** 17 days of failed logins that add up to about 96,000, with one noisy day, oldest first. */
function dailyFailed(): number[] {
  const share = Math.round(TOTAL_FAILED / DAYS_REPORTED)
  return Array.from({ length: DAYS_REPORTED }, (_, day) => (day === 11 ? share * 3 : Math.round(share * (0.4 + ((day * 7) % 10) / 12))))
}

const FAILED_7_DAYS = 41_300
const FAILED_24_HOURS = 5_900

const windows = {
  h24: { failed: FAILED_24_HOURS, blocked: 3 },
  d7: { failed: FAILED_7_DAYS, blocked: 12 },
  d30: { failed: TOTAL_FAILED, blocked: BLOCKED_ADDRESSES },
}

const botNames = [
  { name: 'ubuntu', count: 31_800 }, { name: 'user', count: 22_400 }, { name: 'test', count: 14_900 }, { name: 'admin', count: 11_200 },
  { name: 'postgres', count: 7_300 }, { name: 'root', count: 4_100 }, { name: 'oracle', count: 2_200 }, { name: 'git', count: 1_100 }, { name: 'ftpuser', count: 800 },
]

const blocked = [
  { address: '185.224.128.17', since: ago(2 * HOUR_MS), until: later(22 * HOUR_MS), attempts: 12 },
  { address: '45.148.10.92', since: ago(9 * HOUR_MS), until: later(15 * HOUR_MS), attempts: 8 },
  { address: '92.118.39.61', since: ago(3 * DAY_MS), until: ago(2 * DAY_MS), attempts: 31 },
]

const keyLogins = [
  { method: 'key', user: 'kurnia', address: '202.72.223.27', count: 214, last_seen: ago(HOUR_MS / 2) },
  { method: 'key', user: 'luca', address: '198.51.100.23', count: 38, last_seen: ago(5 * HOUR_MS) },
  { method: 'key', user: 'kurnia', address: '203.0.113.88', count: 9, last_seen: ago(4 * DAY_MS) },
]

const healthyBaseline = { password_login: false, ban_tool: 'running', firewall: true, auto_updates: true, starts_after_reboot: true, pending_updates: 0 }

const machine = (id: string, os: string, extra: Json): Json => ({
  id, name: id, state: 'online', os, arch: os === 'macos' ? 'arm64' : 'x86_64', ip: '192.168.1.30', cpu_cores: 16, cpu_model: 'Test CPU', ram_total_mb: 65536, disk_total_gb: 1000,
  free_ram_mb: 40000, free_disk_gb: 700, gpu: [], capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, last_seen: new Date().toISOString(),
  settings: { profile: 'custom', labels: [], notes: '', allow_gpu: true, public_chat: false }, problems: [], workloads: [], bundle_version: null, agent_version: '0.9.0',
  engine: { name: os === 'macos' ? 'apple' : 'docker', version: null, ready: true }, ...extra,
})

/** One healthy Linux machine, one Linux machine with password login on and no ban tool, one Mac, and one machine whose helper is too old to report. */
export function securityMachines(): Json[] {
  return [
    machine(HEALTHY, 'linux', { security: { baseline: healthyBaseline, windows, daily_failed: dailyFailed(), blocked, usernames: botNames, logins: keyLogins } }),
    machine(WARNING, 'linux', {
      security: {
        baseline: { password_login: true, ban_tool: 'not_running', firewall: false, auto_updates: true, starts_after_reboot: null, pending_updates: 7 },
        windows: { ...windows, d7: { failed: FAILED_7_DAYS, blocked: 0 } }, daily_failed: dailyFailed(), blocked: [],
        usernames: [{ name: HOSTILE_NAME, count: 900 }, { name: HOSTILE_IMG, count: 400 }, ...botNames.slice(0, 5)],
        logins: [...keyLogins, { method: 'password', user: 'deploy', address: '203.0.113.200', count: 4, last_seen: ago(DAY_MS) }],
      },
    }),
    machine(MAC, 'macos', {
      security: { baseline: { ...healthyBaseline, ban_tool: 'not_available' }, windows: { h24: { failed: 20, blocked: null }, d7: { failed: 140, blocked: null }, d30: { failed: 600, blocked: null } }, daily_failed: [30, 22, 18, 25, 19, 14, 12], blocked: [], usernames: botNames.slice(0, 3), logins: keyLogins.slice(0, 1) },
    }),
    machine(OLD_HELPER, 'linux', { agent_version: '0.3.0' }),
  ]
}
