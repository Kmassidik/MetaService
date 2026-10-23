// A stand-in parent for the GPU memory limit ("shared partition"). Five machines: an NVIDIA PC with 31 GB of which 8 are booked, one whose helper is too old, one with nothing free, one that reports no booking, and one without a GPU.
// Create applies the parent's booking rule (409 gpu_memory_not_available with free_gb when over; the booking grows on success, so the next read shows it) and keeps every create request.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import { reading } from '../monitor/stand-in.ts'
import { isRecord, type Json } from '../support/json.ts'

const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const CARD = 'NVIDIA GeForce RTX 5090'
export const SHARE_PC = 'share-pc'
export const OLD_PC = 'old-pc'
export const FULL_PC = 'full-pc'
export const BLIND_PC = 'blind-pc'
export const PLAIN_PC = 'plain-pc'
export const TOTAL_GB = 31
export const BOOKED_GB = 8
export const LIMITED_VM = 'limited'
export const STOPPED_VM = 'overran'
export const WHOLE_CARD_VM = 'whole-card'
export const HOSTILE_MESSAGE = '<img src=x onerror="window.__limitxss=1"> It used 6 GB of GPU memory; its limit is 4 GB.'
const MAX_LIMIT_GB = 1024
const ACCEPTED = 202

export interface LimitStandIn {
  base: string
  /** The bodies of the create requests the form sent, in order. */
  created: Json[]
  /** Makes the next create answer with this refusal instead of applying the rule. */
  refuseNext: (status: number, error: Json) => void
  stop: () => void
}

const caps = (memoryLimit: boolean) => ({ vm: false, container: true, gpu_in_vm: false, gpu_in_container: true, gpu_memory_limit: memoryLimit })
const nvidia = [{ vendor: 'nvidia', model: CARD }]
const booking = (booked: number, total = TOTAL_GB) => ({ total_gb: total, booked_gb: booked, free_gb: total - booked })

const container = (id: string, extra: Json): Json => ({ id, name: id, kind: 'container', state: 'running', cpu: 2, ram_mb: 4096, disk_gb: 40, gpu_mode: 'container', address: null, bundle_version: null, gpu_memory_gb: null, ...extra })

const overLimitReason = (message: string): Json => ({ exit_code: null, log_tail: '', code: 'gpu_memory_over_limit', message, used_gb: 6, limit_gb: 4 })

function machine(id: string, gpu: Json[], capabilities: Json, gpuBooking: Json | null, workloads: Json[] = []): Json {
  return {
    id, name: id, state: 'online', os: 'linux', arch: 'x86_64', ip: '10.0.0.5', cpu_cores: 16, ram_total_mb: 65536, disk_total_gb: 2000, free_ram_mb: 50000, free_disk_gb: 1500,
    gpu, capabilities, gpu_booking: gpuBooking, last_seen: new Date().toISOString(), settings: { profile: 'custom', labels: [] }, problems: [], workloads, bundle_version: null, agent_version: '0.2.0', engine: { name: 'incus', version: '6.0.0', ready: true },
  }
}

const IMAGES: Json = { helper: 'answered', images: [{ id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null },
  { id: 'openclaw', title: 'OpenClaw', description: 'OpenClaw.', state: 'planned', ready: false, available: false, reason: 'Coming soon' },
  { id: 'hermes', title: 'Hermes', description: 'Hermes.', state: 'planned', ready: false, available: false, reason: 'Waiting' }] }
const refusal = (code: string, message: string, extra: Json = {}) => ({ error: { code, message, ...extra } })

export function startLimitStandIn(dist: string): LimitStandIn {
  const created: Json[] = []
  let forced: { status: number; error: Json } | null = null
  const machines: Json[] = [
    machine(SHARE_PC, nvidia, caps(true), booking(BOOKED_GB), [
      container(LIMITED_VM, { gpu_memory_gb: 4 }),
      container(STOPPED_VM, { state: 'stopped', gpu_memory_gb: 4, stopped_reason: overLimitReason(HOSTILE_MESSAGE) }),
      container(WHOLE_CARD_VM, {}),
    ]),
    machine(OLD_PC, nvidia, caps(false), null),
    machine(FULL_PC, nvidia, caps(true), booking(TOTAL_GB)),
    machine(BLIND_PC, nvidia, caps(true), null),
    machine(PLAIN_PC, [], { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, null),
  ]
  const reply = (body: unknown, status = 200) => Response.json(body, { status })
  const missing = () => reply(refusal('not_found', 'no such thing'), 404)
  const find = (id: string): Json | undefined => machines.find((entry) => entry.id === id)

  /** The parent's rule for a limit on a machine, or null when the order may go through. */
  function limitRefusal(target: Json, limit: number): Response | null {
    const gpuBooking = isRecord(target.gpu_booking) ? target.gpu_booking : null
    const capabilities = isRecord(target.capabilities) ? target.capabilities : {}
    if (capabilities.gpu_memory_limit !== true) return reply(refusal('helper_too_old', 'Update the helper on this machine first.'), 409)
    if (gpuBooking === null) return reply(refusal('gpu_memory_unknown', "This machine did not say how much GPU memory it has."), 409)
    const free = Number(gpuBooking.free_gb)
    if (limit <= free) return null
    return reply(refusal('gpu_memory_not_available', `Only ${free} GB of the card's ${gpuBooking.total_gb} GB is still free to book.`, { free_gb: free }), 409)
  }

  function book(target: Json, limit: number, name: string): void {
    const gpuBooking = isRecord(target.gpu_booking) ? target.gpu_booking : booking(0)
    const booked = Number(gpuBooking.booked_gb) + limit
    target.gpu_booking = booking(booked, Number(gpuBooking.total_gb))
    const workloads = Array.isArray(target.workloads) ? target.workloads : []
    workloads.push(container(name, { gpu_memory_gb: limit }))
  }

  function create(sent: Json): Response {
    created.push(sent)
    if (forced) {
      const answer = forced
      forced = null
      return reply({ error: answer.error }, answer.status)
    }
    const target = find(String(sent.machine))
    const limit = sent.gpu_memory_gb
    const name = String(sent.name)
    if (limit !== undefined && (typeof limit !== 'number' || !Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT_GB || sent.gpu_mode !== 'container')) return reply(refusal('invalid_input', 'gpu_memory_gb must be a whole number from 1 to 1024, with gpu_mode container.'), 400)
    if (!target) return missing()
    const refused = typeof limit === 'number' ? limitRefusal(target, limit) : null
    if (refused) return refused
    if (typeof limit === 'number') book(target, limit, name)
    return reply({ command: { id: `c-${created.length}`, machine: String(target.id), type: 'create', state: 'succeeded', created_at: new Date().toISOString(), params: { name }, result: { workload_id: name } } }, ACCEPTED)
  }

  function api(path: string, method: string, body: string): Response {
    if (path === '/api/session') return reply({ username: 'kurnia', csrf_token: 'test' })
    if (path === '/api/machines') return reply({ machines })
    if (path === '/api/workloads' && method === 'POST') {
      const sent: unknown = JSON.parse(body)
      return isRecord(sent) ? create(sent) : reply(refusal('invalid_input', 'not an object'), 400)
    }
    if (path.endsWith('/images')) return reply(IMAGES)
    if (path.endsWith('/stats/history')) return reply({ interval_seconds: 10, points: [] })
    if (path.endsWith('/stats')) return reply({ state: 'online', last_seen: new Date().toISOString(), fetched_at: new Date().toISOString(), stats: reading(created.length + 1, 'studio', false) })
    if (path === '/api/commands') return reply({ commands: [] })
    if (path === '/api/bundles') return reply({ bundles: [], pinned: null })
    if (path === '/api/brain') return reply({ configured: false, usage: [] })
    if (path === '/api/remote/machines') return reply({ machines: [] })
    const found = find(/^\/api\/machines\/([a-z0-9-]+)/.exec(path)?.[1] ?? '')
    return found ? reply({ ...found, box: null, agent_port: null, ruvio: null }) : missing()
  }

  function page(path: string): Response {
    const wanted = join(dist, path === '/' ? 'index.html' : path)
    const file = existsSync(wanted) && statSync(wanted).isFile() ? wanted : join(dist, 'index.html')
    return new Response(readFileSync(file), { headers: { 'Content-Type': CONTENT_TYPES[extname(file)] ?? 'application/octet-stream' } })
  }

  const server = createServer(async (incoming, outgoing) => {
    const chunks: Buffer[] = []
    for await (const chunk of incoming) chunks.push(Buffer.from(chunk))
    const path = new URL(`http://127.0.0.1${incoming.url ?? '/'}`).pathname
    const response = path.startsWith('/api/') ? api(path, incoming.method ?? 'GET', Buffer.concat(chunks).toString()) : page(path)
    outgoing.writeHead(response.status, Object.fromEntries(response.headers))
    outgoing.end(Buffer.from(await response.arrayBuffer()))
  })
  server.listen(0, '127.0.0.1')
  const address = server.address()
  if (address === null || typeof address === 'string') throw new Error('the stand-in parent has no port')
  return { base: `http://127.0.0.1:${address.port}`, created, refuseNext: (status, error) => { forced = { status, error } }, stop: () => void server.close() }
}
