// A stand-in parent for the CPU settings of a new VM (sockets, CPU type, extra flags, a container's CPU limit). Four machines: a Linux PC whose helper offers everything,
// one that offers a CPU type and the aes flag only, one with an older helper that offers nothing, and a Mac. Create applies the parent's rules (400 for a field on the wrong kind,
// 409 missing_capability for what the machine does not offer) and keeps every create request.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import { isRecord, type Json } from '../support/json.ts'

const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
export const CPU_PC = 'cpu-pc'
export const TYPES_PC = 'types-pc'
export const OLD_PC = 'old-pc'
export const MAC = 'mac-studio'
/** What the CPU PC's helper says its CPU is, a hostile name on the types PC (markup and 300 characters), none on the older helper. */
export const CPU_PC_NAME = 'AMD Ryzen 9 5950X 16-Core Processor'
export const HOSTILE_NAME = `<script>window.__cpu=1</script>${'W'.repeat(300)}`
export const MODELS = ['host', 'EPYC', 'EPYC-Rome', 'EPYC-Milan', 'EPYC-Genoa', 'Skylake-Server', 'Icelake-Server', 'kvm64']
const ACCEPTED = 202
const VM_ONLY = ['cpu_sockets', 'cpu_type', 'cpu_flags']

export interface CpuStandIn {
  base: string
  /** The bodies of the create requests the form sent, in order. */
  created: Json[]
  /** Makes the next create answer with this refusal instead of applying the rules. */
  refuseNext: (status: number, error: Json) => void
  stop: () => void
}

const kinds = { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }

function machine(id: string, os: string, arch: string, capabilities: Json, cpuModel?: string): Json {
  return {
    id, name: id, state: 'online', os, arch, ip: '10.0.0.7', cpu_cores: 32, ...(cpuModel === undefined ? {} : { cpu_model: cpuModel }), ram_total_mb: 65536, disk_total_gb: 2000, free_ram_mb: 50000, free_disk_gb: 1500,
    gpu: [], capabilities, last_seen: new Date().toISOString(), settings: { profile: 'custom', labels: [] }, problems: [], workloads: [], bundle_version: null, agent_version: '0.2.0', engine: { name: 'incus', version: '7.3', ready: true },
  }
}

const IMAGES: Json = { helper: 'answered', images: [{ id: 'blank', title: 'Ubuntu Server 24.04 LTS', description: 'Plain Ubuntu with the usual server tools. Nothing else.', state: 'ready', ready: true, available: true, reason: null },
  { id: 'openclaw', title: 'OpenClaw', description: 'Installs after the VM starts, about 2 minutes', state: 'ready', ready: true, available: true, reason: null },
  { id: 'hermes', title: 'Hermes', description: 'Installs after the VM starts, about 2 minutes', state: 'ready', ready: true, available: true, reason: null }] }
const refusal = (code: string, message: string) => ({ error: { code, message } })

/** What the machine offers, read the way the parent reads a heartbeat. */
function offered(target: Json): { models: string[]; topology: boolean; flags: string[]; limit: boolean } {
  const capabilities = isRecord(target.capabilities) ? target.capabilities : {}
  const list = (value: unknown) => (Array.isArray(value) ? value.map(String) : [])
  return { models: ['host', ...list(capabilities.cpu_models).filter((model) => model !== 'host')], topology: capabilities.cpu_topology === true, flags: list(capabilities.cpu_flags), limit: capabilities.cpu_limit === true }
}

/** The parent's rules for the CPU fields of an order, or null when it may go through. */
function cpuRefusal(target: Json, sent: Json): [number, Json] | null {
  const kind = String(sent.kind)
  if (kind !== 'vm' && VM_ONLY.some((key) => key in sent)) return [400, refusal('invalid_input', 'cpu_sockets, cpu_type and cpu_flags are only for a VM')]
  if (kind !== 'container' && 'cpu_limit_percent' in sent) return [400, refusal('invalid_input', 'cpu_limit_percent is only for a container')]
  const offer = offered(target)
  if (typeof sent.cpu_sockets === 'number' && sent.cpu_sockets > 1 && !offer.topology) return [409, refusal('missing_capability', 'This machine cannot spread a VM over sockets. Update its helper.')]
  if (typeof sent.cpu_type === 'string' && !offer.models.includes(sent.cpu_type)) return [409, refusal('missing_capability', `This machine cannot set the CPU type ${sent.cpu_type}. Update its helper, or pick host.`)]
  const flags = isRecord(sent.cpu_flags) ? Object.keys(sent.cpu_flags) : []
  const missing = flags.find((flag) => !offer.flags.includes(flag))
  if (missing !== undefined) return [409, refusal('missing_capability', `This machine cannot switch the ${missing} flag. Update its helper.`)]
  if ('cpu_limit_percent' in sent && !offer.limit) return [409, refusal('missing_capability', "This machine cannot cap a container's CPU time. Update its helper.")]
  return null
}

export function startCpuStandIn(dist: string): CpuStandIn {
  const created: Json[] = []
  let forced: { status: number; error: Json } | null = null
  const machines: Json[] = [
    machine(CPU_PC, 'linux', 'x86_64', { ...kinds, cpu_models: MODELS, cpu_topology: true, cpu_flags: ['nested-virt', 'aes'], cpu_limit: true }, CPU_PC_NAME),
    machine(TYPES_PC, 'linux', 'x86_64', { ...kinds, cpu_models: ['host', 'EPYC'], cpu_flags: ['aes'] }, HOSTILE_NAME),
    machine(OLD_PC, 'linux', 'x86_64', kinds),
    machine(MAC, 'macos', 'arm64', kinds, 'Apple M4'),
  ]
  const reply = (body: unknown, status = 200) => Response.json(body, { status })
  const missing = () => reply(refusal('not_found', 'no such thing'), 404)
  const find = (id: string): Json | undefined => machines.find((entry) => entry.id === id)

  function create(sent: Json): Response {
    created.push(sent)
    if (forced) {
      const answer = forced
      forced = null
      return reply({ error: answer.error }, answer.status)
    }
    const target = find(String(sent.machine))
    if (!target) return missing()
    const refused = cpuRefusal(target, sent)
    if (refused) return reply(refused[1], refused[0])
    const name = String(sent.name)
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
