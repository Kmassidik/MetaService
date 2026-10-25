// A stand-in parent for the Storage tab test. It holds "dgx spark" (a Linux arm64 machine with a 4 TB disk that has never been scanned)
// and "mac-studio" (whose helper has no storage route). A scan "runs" for SCAN_MS with climbing numbers, then the map in sparkMap.ts is served.
// It counts the scans the page asks for. It is not the parent: the parent's own checks have their own tests.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import { sparkMap } from './sparkMap.ts'

const CSRF = 'test-csrf-token'
export const SCAN_MS = 1500
const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }

function machine(id: string, name: string, os: string, more: Record<string, unknown> = {}) {
  return {
    id, name, state: 'online', os, arch: 'arm64', ip: '192.168.1.30', cpu_cores: 20, cpu_model: 'Cortex-X925', ram_total_mb: 124620, disk_total_gb: 4031, free_ram_mb: 116000, free_disk_gb: 3600,
    gpu: [], capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, last_seen: new Date().toISOString(),
    settings: { profile: 'custom', labels: [], notes: '', allow_gpu: true, public_chat: false }, problems: [], workloads: [], bundle_version: null, agent_version: '0.1.0',
    engine: { name: 'incus', version: '6.0.0', ready: true }, agent_build: null, update: { available: false, current_build: null, newest_build: null, reason: null }, ...more,
  }
}

export interface StoragePlan {
  /** True: the machine has a map already when the page opens. */
  scanned: boolean
}

export interface FakeParent {
  base: string
  /** How many scans the page asked for. */
  scans: () => number
  stop: () => void
}

export function startFakeParent(dist: string, plan: StoragePlan = { scanned: false }): FakeParent {
  const machines = [machine('spark-20ec', 'dgx spark', 'linux'), machine('mac-studio', 'mac-studio', 'macos', { engine: { name: 'apple', version: null, ready: true } })]
  let started: number | null = plan.scanned ? Date.now() - SCAN_MS - 60_000 : null
  let finished: number | null = plan.scanned ? (started ?? 0) + SCAN_MS : null
  let scans = 0
  /** When the last scan ended: its map stays on offer while the next one runs, as the helper keeps it. */
  let lastEnded: number | null = finished

  const reply = (body: unknown, status = 200): Response => Response.json(body, { status })

  function storage() {
    const now = Date.now()
    if (started !== null && finished === null && now - started >= SCAN_MS) {
      finished = started + SCAN_MS
      lastEnded = finished
    }
    const scanning = started !== null && finished === null
    const share = scanning && started !== null ? (now - started) / SCAN_MS : 0
    const map = lastEnded === null ? null : sparkMap(new Date(lastEnded), SCAN_MS / 1000)
    return { scanning, progress: scanning ? { entries: Math.round(share * 1_400_000), bytes: Math.round(share * 400 * 1024 ** 3) } : null, error: null, map }
  }

  function api(request: Request, path: string): Response {
    const id = /^\/api\/machines\/([a-z0-9-]+)/.exec(path)?.[1] ?? ''
    if (path === '/api/session') return reply({ username: 'kurnia', csrf_token: CSRF })
    if (path === '/api/machines') return reply({ machines })
    if (path === '/api/commands') return reply({ commands: [] })
    if (path === '/api/bundles') return reply({ bundles: [], pinned: null })
    if (path === '/api/brain') return reply({ configured: false, usage: [] })
    if (path === '/api/remote/machines') return reply({ machines: [] })
    if (path.endsWith('/storage') || path.endsWith('/storage/scan')) {
      if (id === 'mac-studio') return reply({ state: 'old_helper', storage: null }, request.method === 'POST' ? 202 : 200)
      if (request.method === 'POST') {
        if (request.headers.get('x-csrf-token') !== CSRF) return reply({ error: { code: 'csrf', message: 'bad token' } }, 403)
        scans += 1
        if (!storage().scanning) {
          started = Date.now()
          finished = null
        }
        return reply({ state: 'online', storage: storage() }, 202)
      }
      return reply({ state: 'online', storage: storage() })
    }
    const found = machines.find((entry) => entry.id === id)
    return found ? reply({ ...found, box: '~/metaservice-box', agent_port: 9101, ruvio: null }) : reply({ error: { code: 'not_found', message: 'no such machine' } }, 404)
  }

  const server = createServer((incoming, outgoing) => {
    incoming.resume()
    incoming.on('end', async () => {
      const headers = new Headers()
      for (const [name, value] of Object.entries(incoming.headers)) if (typeof value === 'string') headers.set(name, value)
      const request = new Request(`http://127.0.0.1${incoming.url ?? '/'}`, { method: incoming.method ?? 'GET', headers })
      const path = new URL(request.url).pathname
      let response: Response
      if (path.startsWith('/api/')) response = api(request, path)
      else {
        const wanted = join(dist, path === '/' ? 'index.html' : path)
        const file = existsSync(wanted) && statSync(wanted).isFile() ? wanted : join(dist, 'index.html')
        response = new Response(readFileSync(file), { headers: { 'Content-Type': CONTENT_TYPES[extname(file)] ?? 'application/octet-stream' } })
      }
      outgoing.writeHead(response.status, Object.fromEntries(response.headers))
      outgoing.end(Buffer.from(await response.arrayBuffer()))
    })
  })
  server.listen(0, '127.0.0.1')
  const address = server.address()
  if (address === null || typeof address === 'string') throw new Error('the stand-in parent has no port')
  return { base: `http://127.0.0.1:${address.port}`, scans: () => scans, stop: () => void server.close() }
}
