// A stand-in parent for the monitor test. It answers what the panel asks and gives every machine a reading that changes at each call.
// Five machines: "studio" (16 cores, 32 threads, one GPU, every optional number, a hostile process name), "mini" (2 cores, 4 threads; can be taken offline), "oldbox" (its helper is too old),
// "mac" (a Mac: 10 cores, clusters, four CPU states, no frequency or temperature) and "bare" (an 8-core Mac that sends none of the optional numbers).
// It also keeps an hour of readings per machine for the history route and counts how often that route is asked.
// It counts how often each stats route is asked, so the test can compare the page with the list.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import type { Json } from '../support/json.ts'

const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const GIB = 1024 ** 3
export const HOSTILE_NAME = '<img src=x onerror=alert(1)>'
export const HOSTILE_USER = '<script>alert(2)</script>'
const STUDIO_THREADS = 32
const STUDIO_CORES = 16
const MAC_CORES = 10
const PLAIN_THREADS = 4
const PLAIN_CORES = 2
const BARE_CORES = 8
const HISTORY_POINTS = 360
const HISTORY_STEP_SECONDS = 10
const MS_PER_SECOND = 1000
const PERCENT_SPAN = 60
export const PROCESS_COUNT = 15

export interface StandIn {
  base: string
  /** When each stats route was asked, per machine, in milliseconds. */
  asked: Record<string, number[]>
  /** The part of `asked` that wanted the list of programs (processes=1, or no processes parameter at all). */
  askedWithProcesses: Record<string, number[]>
  /** How many times the history route was asked, per machine. */
  askedHistory: Record<string, number>
  /** The raw query of every stats request, in order, so a test can see exactly what the page sent. */
  queries: string[]
  takeOffline: (id: string) => void
  stop: () => void
}

const machine = (id: string, cores: number, os = 'linux'): Json => ({
  id, name: id, state: 'online', os, arch: os === 'macos' ? 'arm64' : 'x86_64', ip: '10.0.0.5', cpu_cores: cores, ram_total_mb: 32768, disk_total_gb: 500, free_ram_mb: 16000, free_disk_gb: 300,
  gpu: [], capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, last_seen: new Date().toISOString(), settings: { profile: 'custom', labels: [] }, problems: [],
  workloads: id === 'studio' ? [{ id: 'vm1', name: 'vm1', kind: 'vm', state: 'running', cpu: 4, ram_mb: 8192, disk_gb: 80 }] : [], bundle_version: null, agent_version: '0.2.0', engine: { name: 'incus', version: null, ready: true },
})

type Extras = 'full' | 'mac' | 'none'
interface Kind { threads: number; cores: number; extras: Extras; gpu: boolean }

const KINDS: Record<string, Kind> = {
  studio: { threads: STUDIO_THREADS, cores: STUDIO_CORES, extras: 'full', gpu: true },
  mini: { threads: PLAIN_THREADS, cores: PLAIN_CORES, extras: 'full', gpu: false },
  oldbox: { threads: 2, cores: 2, extras: 'none', gpu: false },
  mac: { threads: MAC_CORES, cores: MAC_CORES, extras: 'mac', gpu: false },
  bare: { threads: BARE_CORES, cores: BARE_CORES, extras: 'none', gpu: false },
}
const kindOf = (id: string): Kind => KINDS[id] ?? { threads: PLAIN_THREADS, cores: PLAIN_THREADS, extras: 'none', gpu: false }

/** The CPU states of one reading, summing to 100; a Mac gives four of them. */
function breakdownOf(call: number, total: number, extras: Extras): Json {
  const system = Number((total * 0.25).toFixed(1))
  const nice = Number((total * 0.02).toFixed(1))
  const user = Number(Math.max(0, total - system - nice).toFixed(1))
  const idle = Number((100 - total).toFixed(1))
  if (extras === 'mac') return { user, system, nice, idle }
  return { user, system, nice, idle, iowait: Number(((call % 5) * 0.4).toFixed(1)), irq: 0.2, softirq: 0.3, steal: 0.1 }
}

/** The optional numbers of a reading for a machine that sends them. */
function extrasOf(kind: Kind, call: number, total: number): { cpu: Json; top: Json; network: Json; process: (index: number) => Json } {
  if (kind.extras === 'none') return { cpu: {}, top: {}, network: {}, process: () => ({}) }
  const clusters = kind.extras === 'mac' ? { clusters: [{ name: 'Performance', logical: 4 }, { name: 'Efficiency', logical: kind.threads - 4 }] } : {}
  const machineOnly = kind.extras === 'full' ? { frequency_mhz: { average: 3600 + (call % 5) * 100, max: 4900 }, temperature_celsius: 55 + (call % 6) } : {}
  return {
    cpu: { physical_cores: kind.cores, core_of: Array.from({ length: kind.threads }, (_, index) => index % kind.cores), breakdown: breakdownOf(call, total, kind.extras), ...clusters, ...machineOnly },
    top: { disk_io: { read_bytes_per_second: 2_000_000 + call * 10_000, write_bytes_per_second: 500_000 + call * 5_000 }, process_count: 412 + (call % 4) },
    network: { errors_in_total: 1, errors_out_total: 0, drops_in_total: Math.floor(call / 3), ...(kind.extras === 'full' ? { drops_out_total: Math.floor(call / 5) } : {}) },
    process: (index) => ({ threads: 1 + index * 2 }),
  }
}

function reading(call: number, id: string, withProcesses: boolean): Json {
  const kind = kindOf(id)
  const cores = kind.threads
  const used = (8 + (call % 8)) * GIB
  const cpuAt = (index: number) => Number((((call * 7 + index * 3) % PERCENT_SPAN) + 5).toFixed(1))
  const more = extrasOf(kind, call, cpuAt(0))
  return {
    taken_at: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), measuring: false, uptime_seconds: 90061 + call,
    cpu: { core_count: cores, total_percent: cpuAt(0), cores_percent: Array.from({ length: cores }, (_, index) => cpuAt(index)), load: { one: 1.5, five: 1.2, fifteen: 1.0 }, ...more.cpu },
    memory: { total_bytes: 32 * GIB, used_bytes: used, cached_bytes: 6 * GIB, free_bytes: 32 * GIB - used - 6 * GIB, swap_total_bytes: 0, swap_used_bytes: 0 },
    disks: [{ mount: '/', name: 'root', fs: 'ext4', total_bytes: 500 * GIB, used_bytes: 200 * GIB, free_bytes: 300 * GIB }],
    network: { received_total_bytes: 1000 * call, sent_total_bytes: 500 * call, received_bytes_per_second: 100000 + call * 1000, sent_bytes_per_second: 20000 + call * 100, ...more.network },
    ...(kind.gpu ? { gpus: [{ name: 'Test GPU 5090', utilization_percent: 40, memory_used_bytes: 2 * GIB, memory_total_bytes: 32 * GIB, temperature_celsius: 55 }] } : {}),
    processes: withProcesses ? processesAt(call).map((one, index) => ({ ...one, ...more.process(index) })) : [],
    ...more.top,
  }
}

/** An hour of readings, one every ten seconds, the way the parent keeps them. */
function historyOf(id: string): Json {
  const kind = kindOf(id)
  const end = Math.floor(Date.now() / MS_PER_SECOND)
  const points = Array.from({ length: HISTORY_POINTS }, (_, index): Json => {
    const call = index + 1
    const total = Number((((call * 7) % PERCENT_SPAN) + 5).toFixed(1))
    return {
      t: end - (HISTORY_POINTS - index) * HISTORY_STEP_SECONDS, cpu_percent: total, load: [1.5, 1.2, 1.0],
      mem_used: (8 + (call % 8)) * GIB, mem_cached: 6 * GIB, mem_total: 32 * GIB, swap_used: 0, swap_total: 0,
      net_in_bps: 100000 + call * 1000, net_out_bps: 20000 + call * 100,
      ...(kind.extras === 'none' ? {} : { cpu_breakdown: breakdownOf(call, total, kind.extras), disk_read: 2_000_000 + call * 10_000, disk_write: 500_000 + call * 5_000, net_drops: Math.floor(call / 3), processes_count: 412 }),
    }
  })
  return { interval_seconds: HISTORY_STEP_SECONDS, points }
}

/** Fifteen programs, busiest first: the hostile one, "node", then thirteen quiet workers run by "service". */
function processesAt(call: number): Json[] {
  const workers = Array.from({ length: PROCESS_COUNT - 2 }, (_, index) => ({ pid: index + 3, name: `worker-${index + 3}`, user: 'service', cpu_percent: 10 - index * 0.5, memory_bytes: GIB / 2 }))
  return [{ pid: 1, name: HOSTILE_NAME, user: HOSTILE_USER, cpu_percent: 80 + call, memory_bytes: 5 * GIB }, { pid: 2, name: 'node', user: 'kurnia', cpu_percent: 12.5, memory_bytes: GIB }, ...workers]
}

export function startStandIn(dist: string): StandIn {
  const machines = [machine('studio', STUDIO_THREADS), machine('mini', PLAIN_THREADS), machine('oldbox', 2), machine('mac', MAC_CORES, 'macos'), machine('bare', BARE_CORES, 'macos')]
  const asked: Record<string, number[]> = { studio: [], mini: [], oldbox: [], mac: [], bare: [] }
  const askedWithProcesses: Record<string, number[]> = { studio: [], mini: [], oldbox: [], mac: [], bare: [] }
  const askedHistory: Record<string, number> = { studio: 0, mini: 0, oldbox: 0, mac: 0, bare: 0 }
  const queries: string[] = []
  const offline = new Set<string>()
  const last = new Map<string, Json>()
  const reply = (body: unknown, status = 200) => Response.json(body, { status })
  const stateOf = (entry: Json) => (offline.has(String(entry.id)) ? 'offline' : 'online')

  function stats(id: string, search: string): Response {
    const list = asked[id]
    if (!list) return reply({ error: { code: 'not_found', message: 'no such thing' } }, 404)
    const withProcesses = new URLSearchParams(search).get('processes') !== '0'
    queries.push(search)
    list.push(Date.now())
    if (withProcesses) askedWithProcesses[id]?.push(Date.now())
    const lastSeen = new Date().toISOString()
    if (id === 'oldbox') return reply({ state: 'old_helper', last_seen: lastSeen, fetched_at: null, stats: null })
    if (offline.has(id)) return reply({ state: 'offline', last_seen: new Date(Date.now() - 180000).toISOString(), fetched_at: null, stats: last.get(id) ?? null })
    const one = reading(list.length, id, withProcesses)
    last.set(id, one)
    return reply({ state: 'online', last_seen: lastSeen, fetched_at: lastSeen, stats: one })
  }

  function history(id: string): Response {
    if (askedHistory[id] === undefined) return reply({ error: { code: 'not_found', message: 'no such thing' } }, 404)
    askedHistory[id] += 1
    return reply(id === 'oldbox' ? { interval_seconds: HISTORY_STEP_SECONDS, points: [] } : historyOf(id))
  }

  function api(path: string, search: string): Response {
    const id = /^\/api\/machines\/([a-z0-9-]+)/.exec(path)?.[1] ?? ''
    if (path === '/api/session') return reply({ username: 'kurnia', csrf_token: 'test' })
    if (path === '/api/machines') return reply({ machines: machines.map((entry) => ({ ...entry, state: stateOf(entry) })) })
    if (path.endsWith('/stats/history')) return history(id)
    if (path.endsWith('/stats')) return stats(id, search)
    if (path === '/api/commands') return reply({ commands: [] })
    if (path === '/api/bundles') return reply({ bundles: [], pinned: null })
    if (path === '/api/brain') return reply({ configured: false, usage: [] })
    if (path === '/api/remote/machines') return reply({ machines: [] })
    const found = machines.find((entry) => entry.id === id)
    return found ? reply({ ...found, state: stateOf(found), box: null, agent_port: null, ruvio: null }) : reply({ error: { code: 'not_found', message: 'no such thing' } }, 404)
  }

  function answer(url: string): Response {
    const { pathname: path, search } = new URL(url)
    if (path.startsWith('/api/')) return api(path, search)
    const wanted = join(dist, path === '/' ? 'index.html' : path)
    const file = existsSync(wanted) && statSync(wanted).isFile() ? wanted : join(dist, 'index.html')
    return new Response(readFileSync(file), { headers: { 'Content-Type': CONTENT_TYPES[extname(file)] ?? 'application/octet-stream' } })
  }

  const server = createServer(async (incoming, outgoing) => {
    const response = answer(`http://127.0.0.1${incoming.url ?? '/'}`)
    outgoing.writeHead(response.status, Object.fromEntries(response.headers))
    outgoing.end(Buffer.from(await response.arrayBuffer()))
  })
  server.listen(0, '127.0.0.1')
  const address = server.address()
  if (address === null || typeof address === 'string') throw new Error('the stand-in parent has no port')
  return { base: `http://127.0.0.1:${address.port}`, asked, askedWithProcesses, askedHistory, queries, takeOffline: (id) => void offline.add(id), stop: () => void server.close() }
}
