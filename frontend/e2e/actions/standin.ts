// A stand-in Root for the button tests: it serves the built panel and answers the VM calls slowly, refuses them, or never answers, on command.
// It exists because the real Root answers a start in a few milliseconds, too fast to press a button twice while it works.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { extname, join } from 'node:path'
import { panelDist } from '../support/paths.ts'
import { wait } from '../support/net.ts'

const CSRF = 'test-token'
const TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const VM_CALL = /^\/api\/machines\/([^/]+)\/workloads\/([^/]+)\/(start|stop|delete)$/

export interface Behaviour {
  /** How long every VM call takes to answer. */
  delayMs: number
  /** When set, the next VM calls are refused with this message (until cleared). */
  refuseWith: string | null
  /** When true, VM calls are never answered. */
  hang: boolean
}

export interface StandIn {
  base: string
  behaviour: Behaviour
  /** Every VM call that arrived, as "start vm2", in order. */
  calls: string[]
  reset: () => void
  close: () => void
}

type Json = Record<string, unknown>

function machine(id: string, workloads: Json[]): Json {
  return {
    id, name: id, state: 'online', os: 'linux', arch: 'amd64', ip: '192.168.1.2', cpu_cores: 8, ram_total_mb: 32768, disk_total_gb: 500, free_ram_mb: 20000, free_disk_gb: 400, gpu: [],
    capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: true }, last_seen: new Date().toISOString(),
    settings: { profile: 'custom', labels: [], notes: '', allow_gpu: true }, problems: [], bundle_version: null, agent_version: '0.2.0', agent_build: 'a'.repeat(64),
    update: { available: false, current_build: 'a'.repeat(64), newest_build: 'a'.repeat(64), reason: null }, engine: { name: 'incus', version: '6', ready: true }, workloads,
  }
}

const vm = (id: string, state: string): Json => ({ id, name: id, kind: 'vm', state, cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none' })

const fleet = (): Json[] => [machine('studio', [vm('vm1', 'running'), vm('vm2', 'stopped'), vm('vm3', 'stopped')])]

const order = (type: string, id: string): Json => ({ command: { id, type, machine: 'studio', workload_id: null, state: 'running', created_at: new Date().toISOString(), params: {} } })

function send(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { 'Content-Type': 'application/json' })
  response.end(JSON.stringify(body))
}

function serveFile(path: string, response: ServerResponse): void {
  const wanted = join(panelDist, path === '/' ? 'index.html' : path)
  const file = existsSync(wanted) && statSync(wanted).isFile() ? wanted : join(panelDist, 'index.html')
  response.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' })
  response.end(readFileSync(file))
}

export async function startStandIn(): Promise<StandIn> {
  let machines = fleet()
  const behaviour: Behaviour = { delayMs: 0, refuseWith: null, hang: false }
  const calls: string[] = []

  /** Applies a start, stop or delete the way the helper would, once the call is accepted. */
  function apply(machineId: string, workloadId: string, action: string): void {
    const owner = machines.find((entry) => entry.id === machineId)
    const workloads = owner?.workloads
    if (!owner || !Array.isArray(workloads)) return
    if (action === 'delete') owner.workloads = workloads.filter((entry) => entry.id !== workloadId)
    const target = workloads.find((entry) => entry.id === workloadId)
    if (target && action === 'start') target.state = 'running'
    if (target && action === 'stop') target.state = 'stopped'
  }

  async function vmCall(match: RegExpExecArray, response: ServerResponse): Promise<void> {
    const [, machineId = '', workloadId = '', action = ''] = match
    calls.push(`${action} ${workloadId}`)
    if (behaviour.hang) return
    await wait(behaviour.delayMs)
    if (behaviour.refuseWith !== null) return send(response, 409, { error: { code: 'refused', message: behaviour.refuseWith } })
    apply(machineId, workloadId, action)
    send(response, 202, order(action, `order-${calls.length}`))
  }

  async function api(request: IncomingMessage, response: ServerResponse, path: string): Promise<void> {
    if (path === '/api/session') return send(response, 200, { username: 'kurnia', csrf_token: CSRF })
    if (path === '/api/auth/status') return send(response, 200, { configured: true, signedIn: true, min_password_length: 8 })
    const call = VM_CALL.exec(path)
    if (call && request.method === 'POST') return vmCall(call, response)
    if (path === '/api/machines') return send(response, 200, { machines })
    if (path === '/api/commands') return send(response, 200, { commands: [] })
    if (path === '/api/bundles') return send(response, 200, { bundles: [], pinned: null })
    if (path === '/api/brain') return send(response, 200, { configured: true, usage: [] })
    if (path === '/api/remote/machines') return send(response, 200, { machines: [] })
    send(response, 404, { error: { code: 'not_found', message: path } })
  }

  const server: Server = createServer((request, response) => {
    const path = new URL(request.url ?? '/', 'http://stand-in').pathname
    if (path.startsWith('/api/')) void api(request, response, path)
    else serveFile(path, response)
  })
  await new Promise<void>((done) => server.listen(0, '127.0.0.1', done))
  const address = server.address()
  if (address === null || typeof address === 'string') throw new Error('the stand-in got no port')

  return {
    base: `http://127.0.0.1:${address.port}`,
    behaviour,
    calls,
    reset() {
      machines = fleet()
      calls.length = 0
      Object.assign(behaviour, { delayMs: 0, refuseWith: null, hang: false })
    },
    close() {
      server.closeAllConnections()
      server.close()
    },
  }
}
