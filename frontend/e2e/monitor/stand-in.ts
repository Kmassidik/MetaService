// A stand-in parent for the monitor test. It answers what the panel asks and gives every machine a reading that changes at each call.
// Three machines: "studio" (32 cores, one GPU, a hostile process name), "mini" (can be taken offline), "oldbox" (its helper is too old).
// It counts how often each stats route is asked, so the test can compare the page with the list.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import type { Json } from '../support/json.ts'

const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' }
const GIB = 1024 ** 3
export const HOSTILE_NAME = '<img src=x onerror=alert(1)>'
export const HOSTILE_USER = '<script>alert(2)</script>'
const STUDIO_CORES = 32
const PERCENT_SPAN = 60
export const PROCESS_COUNT = 15

export interface StandIn {
  base: string
  /** When each stats route was asked, per machine, in milliseconds. */
  asked: Record<string, number[]>
  takeOffline: (id: string) => void
  stop: () => void
}

const machine = (id: string, cores: number): Json => ({
  id, name: id, state: 'online', os: 'linux', arch: 'x86_64', ip: '10.0.0.5', cpu_cores: cores, ram_total_mb: 32768, disk_total_gb: 500, free_ram_mb: 16000, free_disk_gb: 300,
  gpu: [], capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, last_seen: new Date().toISOString(), settings: { profile: 'custom', labels: [] }, problems: [],
  workloads: id === 'studio' ? [{ id: 'vm1', name: 'vm1', kind: 'vm', state: 'running', cpu: 4, ram_mb: 8192, disk_gb: 80 }] : [], bundle_version: null, agent_version: '0.2.0', engine: { name: 'incus', version: null, ready: true },
})

function reading(call: number, cores: number, withGpu: boolean): Json {
  const used = (8 + (call % 8)) * GIB
  const cpuAt = (index: number) => Number((((call * 7 + index * 3) % PERCENT_SPAN) + 5).toFixed(1))
  return {
    taken_at: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), measuring: false, uptime_seconds: 90061 + call,
    cpu: { core_count: cores, total_percent: cpuAt(0), cores_percent: Array.from({ length: cores }, (_, index) => cpuAt(index)), load: { one: 1.5, five: 1.2, fifteen: 1.0 } },
    memory: { total_bytes: 32 * GIB, used_bytes: used, cached_bytes: 6 * GIB, free_bytes: 32 * GIB - used - 6 * GIB, swap_total_bytes: 0, swap_used_bytes: 0 },
    disks: [{ mount: '/', name: 'root', fs: 'ext4', total_bytes: 500 * GIB, used_bytes: 200 * GIB, free_bytes: 300 * GIB }],
    network: { received_total_bytes: 1000 * call, sent_total_bytes: 500 * call, received_bytes_per_second: 100000 + call * 1000, sent_bytes_per_second: 20000 + call * 100 },
    ...(withGpu ? { gpus: [{ name: 'Test GPU 5090', utilization_percent: 40, memory_used_bytes: 2 * GIB, memory_total_bytes: 32 * GIB, temperature_celsius: 55 }] } : {}),
    processes: processesAt(call),
  }
}

/** Fifteen programs, busiest first: the hostile one, "node", then thirteen quiet workers run by "service". */
function processesAt(call: number): Json[] {
  const workers = Array.from({ length: PROCESS_COUNT - 2 }, (_, index) => ({ pid: index + 3, name: `worker-${index + 3}`, user: 'service', cpu_percent: 10 - index * 0.5, memory_bytes: GIB / 2 }))
  return [{ pid: 1, name: HOSTILE_NAME, user: HOSTILE_USER, cpu_percent: 80 + call, memory_bytes: 5 * GIB }, { pid: 2, name: 'node', user: 'kurnia', cpu_percent: 12.5, memory_bytes: GIB }, ...workers]
}

export function startStandIn(dist: string): StandIn {
  const machines = [machine('studio', STUDIO_CORES), machine('mini', 4), machine('oldbox', 2)]
  const asked: Record<string, number[]> = { studio: [], mini: [], oldbox: [] }
  const offline = new Set<string>()
  const last = new Map<string, Json>()
  const reply = (body: unknown, status = 200) => Response.json(body, { status })
  const stateOf = (entry: Json) => (offline.has(String(entry.id)) ? 'offline' : 'online')

  function stats(id: string): Response {
    const list = asked[id]
    if (!list) return reply({ error: { code: 'not_found', message: 'no such thing' } }, 404)
    list.push(Date.now())
    const lastSeen = new Date().toISOString()
    if (id === 'oldbox') return reply({ state: 'old_helper', last_seen: lastSeen, fetched_at: null, stats: null })
    if (offline.has(id)) return reply({ state: 'offline', last_seen: new Date(Date.now() - 180000).toISOString(), fetched_at: null, stats: last.get(id) ?? null })
    const one = reading(list.length, id === 'studio' ? STUDIO_CORES : 4, id === 'studio')
    last.set(id, one)
    return reply({ state: 'online', last_seen: lastSeen, fetched_at: lastSeen, stats: one })
  }

  function api(path: string): Response {
    const id = /^\/api\/machines\/([a-z0-9-]+)/.exec(path)?.[1] ?? ''
    if (path === '/api/session') return reply({ username: 'kurnia', csrf_token: 'test' })
    if (path === '/api/machines') return reply({ machines: machines.map((entry) => ({ ...entry, state: stateOf(entry) })) })
    if (path.endsWith('/stats')) return stats(id)
    if (path === '/api/commands') return reply({ commands: [] })
    if (path === '/api/bundles') return reply({ bundles: [], pinned: null })
    if (path === '/api/brain') return reply({ configured: false, usage: [] })
    if (path === '/api/remote/machines') return reply({ machines: [] })
    const found = machines.find((entry) => entry.id === id)
    return found ? reply({ ...found, state: stateOf(found), box: null, agent_port: null, ruvio: null }) : reply({ error: { code: 'not_found', message: 'no such thing' } }, 404)
  }

  function answer(url: string): Response {
    const path = new URL(url).pathname
    if (path.startsWith('/api/')) return api(path)
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
  return { base: `http://127.0.0.1:${address.port}`, asked, takeOffline: (id) => void offline.add(id), stop: () => void server.close() }
}
