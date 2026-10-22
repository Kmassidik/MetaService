// A stand-in parent for the GPU test. It lists five machines (a container-only PC with an NVIDIA card and the toolkit, a bigger one that can also run VMs, a PC with the card but no toolkit,
// a Mac, a plain Linux machine) and answers "Check the GPU" with a scripted answer chosen by the container's id. It keeps every create request, so the test can read what the form sent.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import { isRecord, type Json } from '../support/json.ts'

const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
export const HOSTILE_DETAIL = '<img src=x onerror="window.__gpuxss=1"> <script>window.__gpuxss=2</script>'
export const CARD = 'NVIDIA GeForce RTX 5090'
export const REFUSED_CREATE = 'No machine can share its GPU with a container: a machine needs an NVIDIA GPU and the NVIDIA container toolkit installed.'

/** The containers whose GPU check is scripted, by id. */
export const CHECK_IDS = { smi: 'g-smi', devices: 'g-dev', nothing: 'g-none', hostile: 'g-hostile', down: 'g-down', stopped: 'g-off' } as const

/** The images every machine answers with: Blank, and the two that are listed but not yet available. */
const IMAGES: Json = {
  helper: 'answered',
  images: [
    { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null },
    { id: 'openclaw', title: 'OpenClaw', description: 'OpenClaw.', state: 'planned', ready: false, available: false, reason: 'Coming soon' },
    { id: 'hermes', title: 'Hermes', description: 'Hermes.', state: 'planned', ready: false, available: false, reason: 'Waiting' },
  ],
}

const ANSWERS: Record<string, Json> = {
  [CHECK_IDS.smi]: { gpu_visible: true, how: 'nvidia-smi', detail: `${CARD}, 580.178.04, 32607 MiB`, note: 'The GPU is visible inside, and nvidia-smi can talk to it.' },
  [CHECK_IDS.devices]: { gpu_visible: true, how: 'device nodes', detail: '/dev/nvidia0, /dev/nvidiactl. NVRM version: NVIDIA UNIX x86_64 Kernel Module  580.178.04', note: 'The GPU device is there but nvidia-smi is not installed in this image.' },
  [CHECK_IDS.nothing]: { gpu_visible: false, how: 'none', detail: '', note: 'The GPU is not visible inside: there is no nvidia-smi and no NVIDIA device file.' },
  [CHECK_IDS.hostile]: { gpu_visible: true, how: 'nvidia-smi', detail: HOSTILE_DETAIL, note: '<b>bold</b> note' },
}

export interface GpuStandIn {
  base: string
  /** The bodies of the create requests the form sent. */
  created: Json[]
  stop: () => void
}

const caps = (vm: boolean, gpuInContainer: boolean) => ({ vm, container: true, gpu_in_vm: false, gpu_in_container: gpuInContainer })
const nvidia = [{ vendor: 'nvidia', model: CARD }]

const container = (id: string, gpuMode: string, state = 'running'): Json => ({ id, name: id, kind: 'container', state, cpu: 2, ram_mb: 4096, disk_gb: 40, gpu_mode: gpuMode, address: null, bundle_version: null })

function machine(id: string, os: string, gpu: Json[], capabilities: Json, workloads: Json[] = []): Json {
  return {
    id, name: id, state: 'online', os, arch: os === 'macos' ? 'arm64' : 'x86_64', ip: '10.0.0.5', cpu_cores: 16, ram_total_mb: 65536, disk_total_gb: 2000, free_ram_mb: 50000, free_disk_gb: 1500,
    gpu, capabilities, last_seen: new Date().toISOString(), settings: { profile: 'custom', labels: [] }, problems: [], workloads, bundle_version: null, agent_version: '0.2.0', engine: { name: 'incus', version: '6.0.0', ready: true },
  }
}

const MACHINES: Json[] = [
  machine('rtx-pc', 'linux', nvidia, caps(false, true), [
    ...Object.values(CHECK_IDS).map((id) => container(id, 'container', id === CHECK_IDS.stopped ? 'stopped' : 'running')), container('plain-box', 'none'),
  ]),
  machine('gpu-server', 'linux', nvidia, caps(true, true)),
  machine('rtx-notoolkit', 'linux', nvidia, caps(false, false)),
  machine('mac-studio', 'macos', [{ vendor: 'apple', model: 'Apple M2 Ultra' }], caps(true, false)),
  machine('plain-linux', 'linux', [], caps(true, false)),
]

export function startGpuStandIn(dist: string): GpuStandIn {
  const created: Json[] = []
  const reply = (body: unknown, status = 200) => Response.json(body, { status })
  const missing = () => reply({ error: { code: 'not_found', message: 'no such thing' } }, 404)

  function gpuCheck(path: string): Response {
    const workload = /\/workloads\/([a-z0-9-]+)\/gpu-check$/.exec(path)?.[1] ?? ''
    if (workload === CHECK_IDS.down) return reply({ error: { code: 'unreachable', message: 'the machine did not answer' } }, 502)
    if (workload === CHECK_IDS.stopped) return reply({ error: { code: 'not_running', message: 'start it first: the GPU can only be checked inside a running container' } }, 409)
    const answer = ANSWERS[workload]
    return answer ? reply(answer) : missing()
  }

  function api(path: string, method: string, body: string): Response {
    if (path === '/api/session') return reply({ username: 'kurnia', csrf_token: 'test' })
    if (path === '/api/machines') return reply({ machines: MACHINES })
    if (path === '/api/workloads' && method === 'POST') {
      const sent: unknown = JSON.parse(body)
      if (isRecord(sent)) created.push(sent)
      return reply({ error: { code: 'missing_capability', message: REFUSED_CREATE, resource: 'capability', needed: 1, free: 0 } }, 409)
    }
    if (path.endsWith('/gpu-check')) return gpuCheck(path)
    if (path.endsWith('/images')) return reply(IMAGES)
    if (path.endsWith('/stats')) return reply({ state: 'old_helper', last_seen: new Date().toISOString(), fetched_at: null, stats: null })
    if (path === '/api/commands') return reply({ commands: [] })
    if (path === '/api/bundles') return reply({ bundles: [], pinned: null })
    if (path === '/api/brain') return reply({ configured: false, usage: [] })
    if (path === '/api/remote/machines') return reply({ machines: [] })
    const found = MACHINES.find((entry) => entry.id === (/^\/api\/machines\/([a-z0-9-]+)/.exec(path)?.[1] ?? ''))
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
  return { base: `http://127.0.0.1:${address.port}`, created, stop: () => void server.close() }
}
