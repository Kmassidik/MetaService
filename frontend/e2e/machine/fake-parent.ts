// A stand-in parent for the machine page test: it answers only what the panel asks for and holds one machine shaped like the real mac-studio
// (macOS arm64, 14 cores, 36864 MB, 494 GB, engine Apple, no chat, no VMs, default settings) and a second machine so a name can clash.
// It keeps what the page sends, so the test can look at it. It is not the parent: the parent's own checks have their own tests.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join } from 'node:path'
import { isRecord, type Json } from '../support/json.ts'

const CSRF = 'test-csrf-token'
const CHAT_VERSION = '0.4.0'
/** How long a stand-in install or removal takes, so the page's "turning on…" state can be seen. */
const COMMAND_MS = 1500
const SETTINGS_FIELDS = ['name', 'labels', 'notes', 'allow_gpu', 'ram_reserve_mb', 'disk_reserve_gb', 'ram_allowance_mb', 'disk_allowance_gb', 'vm_max_running', 'vm_cpu', 'vm_ram_mb', 'vm_disk_gb', 'vm_image', 'subdomain', 'ai_model']
const CONTENT_TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const TUNNEL_SINCE_MS = 90 * 60 * 1000
/** How long a stand-in update takes, so "Updating…" can be seen. */
const UPDATE_MS = 1200
const HELPER_UP_TO_DATE = 'c'.repeat(64)

/** The helper program of the stand-in machines: which build mac-studio runs, which one the parent can install, and what pressing "Update helper" gets. */
export interface HelperScenario {
  /** The build mac-studio's helper reports; null is an older helper that does not say. */
  build: string | null
  /** The build the parent can install; null when it has none for this kind of computer. */
  newest: string | null
  /** Why nothing is on offer, when the parent says. */
  reason?: string
  /** What the update route answers, with its status. */
  answer: { status: number; body: Json }
  /** The machine does not answer. */
  offline?: boolean
}

export interface FakeParentOptions {
  /** How many chat versions the parent has built. Zero makes Ruvio unavailable. */
  chatsBuilt: number
  /** The panel files to serve (the built panel). */
  dist: string
  /** The helper programs; left out, every machine is up to date. */
  helper?: HelperScenario
}

export interface FakeParent {
  base: string
  /** Every body PATCHed to the settings route, in order. */
  patches: Json[]
  /** Every Ruvio command the page sent, "install" or "uninstall". */
  commands: string[]
  /** The machines the page asked to update the helper of, in order. */
  updates: string[]
  stop: () => void
}

function studio(): Json {
  return {
    id: 'mac-studio', name: 'mac-studio', state: 'online', os: 'macos', arch: 'arm64', ip: '192.168.1.20', cpu_cores: 14, ram_total_mb: 36864, disk_total_gb: 494,
    free_ram_mb: 21400, free_disk_gb: 402, gpu: [], capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, last_seen: new Date().toISOString(),
    settings: { profile: 'custom', labels: [], notes: '', allow_gpu: true, public_chat: false }, problems: [], workloads: [], bundle_version: null,
    agent_version: null, engine: { name: 'apple', version: null, ready: true },
  }
}

const mini = (): Json => ({ ...studio(), id: 'mac-mini', name: 'mac-mini', ip: '192.168.1.21' })

/** The update part of a machine, the way the parent says it: a different build on offer makes it available. */
function withHelper(machine: Json, helper: HelperScenario, build: string | null): Json {
  const offered = helper.newest !== null && helper.reason === undefined
  const update = { available: offered && build !== helper.newest, current_build: build, newest_build: offered ? helper.newest : null, reason: helper.reason ?? null }
  return { ...machine, agent_build: build, update, ...(helper.offline && machine.id === 'mac-studio' ? { state: 'offline' } : {}) }
}

const reply = (body: unknown, status = 200): Response => Response.json(body, { status })
const refuse = (status: number, code: string, message: string): Response => reply({ error: { code, message } }, status)

/** The patch fields the stand-in accepts, applied to a machine's settings. Names the parent would refuse are refused here too. */
function applyPatch(machine: Json, patch: Json): Json {
  const settings: Json = isRecord(machine.settings) ? { ...machine.settings } : {}
  for (const [key, value] of Object.entries(patch)) {
    if (key === 'name') continue
    if (value === null) delete settings[key]
    else settings[key] = value
  }
  return { ...machine, name: typeof patch.name === 'string' ? patch.name : machine.name, settings }
}

export function startFakeParent(options: FakeParentOptions): FakeParent {
  const helper = options.helper ?? { build: HELPER_UP_TO_DATE, newest: HELPER_UP_TO_DATE, answer: { status: 200, body: {} } }
  const machines: Json[] = [withHelper(studio(), helper, helper.build), withHelper(mini(), helper, helper.newest)]
  const patches: Json[] = []
  const commands: string[] = []
  const updates: string[] = []
  let installed: string | null = null
  let going: 'installing' | 'removing' | null = null
  const bundles = Array.from({ length: options.chatsBuilt }, (_, index) => ({ version: index === 0 ? CHAT_VERSION : `0.${index + 4}.0`, platform: 'any', sha256: 'x', size: 1, pinned: index === 0 }))

  const ruvio = () => ({ installed, pinned: bundles.length ? CHAT_VERSION : null, state: going ?? (installed ? 'on' : bundles.length ? 'off' : 'unavailable') })
  const detail = (machine: Json): Json => ({ ...machine, bundle_version: machine.id === 'mac-studio' ? installed : null, box: '~/metaservice-box', agent_port: 8447, ruvio: machine.id === 'mac-studio' ? ruvio() : null })

  function runCommand(kind: 'install' | 'uninstall'): Response {
    if (kind === 'install' && bundles.length === 0) return refuse(409, 'no_chat_built', 'no chat is built on the parent')
    commands.push(kind)
    going = kind === 'install' ? 'installing' : 'removing'
    setTimeout(() => { installed = kind === 'install' ? CHAT_VERSION : null; going = null }, COMMAND_MS)
    return reply({ command_id: `c-${commands.length}` }, 202)
  }

  /** The Update helper button: the answer takes a moment, and a helper that was updated reports the new build from then on. */
  async function updateHelper(request: Request, id: string): Promise<Response> {
    if (request.headers.get('x-csrf-token') !== CSRF) return refuse(403, 'csrf', 'bad token')
    updates.push(id)
    await new Promise((resolve) => setTimeout(resolve, UPDATE_MS))
    const index = machines.findIndex((entry) => entry.id === id)
    const machine = machines[index]
    if (machine && helper.answer.body.result === 'updated') machines.splice(index, 1, withHelper(machine, helper, helper.newest))
    return reply(helper.answer.body, helper.answer.status)
  }

  async function change(request: Request, id: string): Promise<Response> {
    if (request.headers.get('x-csrf-token') !== CSRF) return refuse(403, 'csrf', 'bad token')
    const patch: unknown = await request.json()
    const machine = machines.find((entry) => entry.id === id)
    if (!isRecord(patch) || !machine) return refuse(400, 'bad_request', 'bad request')
    const unknown = Object.keys(patch).find((key) => !SETTINGS_FIELDS.includes(key))
    if (unknown) return refuse(400, 'bad_request', `unknown field: ${unknown}`)
    if (machines.some((other) => other.id !== id && other.name === patch.name)) return refuse(409, 'machine_exists', 'another machine already has that name')
    patches.push(patch)
    machines.splice(machines.indexOf(machine), 1, applyPatch(machine, patch))
    return reply(detail(machines.find((entry) => entry.id === id) ?? machine))
  }

  async function api(request: Request, path: string): Promise<Response> {
    const machineId = /^\/api\/machines\/([a-z0-9-]+)/.exec(path)?.[1] ?? ''
    if (path === '/api/session') return reply({ username: 'kurnia', csrf_token: CSRF })
    if (path === '/api/machines') return reply({ machines })
    if (request.method === 'PATCH' && path.endsWith('/settings')) return change(request, machineId)
    if (request.method === 'POST' && path.endsWith('/update-helper')) return updateHelper(request, machineId)
    if (path.endsWith('/bundle/install')) return runCommand('install')
    if (path.endsWith('/bundle/uninstall')) return runCommand('uninstall')
    if (path === '/api/commands') return reply({ commands: [] })
    if (path === '/api/bundles') return reply({ bundles, pinned: bundles.length ? CHAT_VERSION : null })
    if (path === '/api/brain') return reply({ configured: false, usage: [] })
    if (path === '/api/remote/machines') return reply({ machines: [{ machine: 'mac-studio', host: '192.168.1.20', ssh_port: 22, ssh_user: 'kurnia', level: 'user', box: '~/metaservice-box', agent_port: 8447, engine: 'apple', has_key: true, tunnel: { state: 'connected', since: new Date(Date.now() - TUNNEL_SINCE_MS).toISOString(), local_port: 41000, failures: 0 } }] })
    const found = machines.find((entry) => entry.id === machineId)
    return found ? reply(detail(found)) : refuse(404, 'not_found', 'no such machine')
  }

  async function answer(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname
    if (path.startsWith('/api/')) return api(request, path)
    const wanted = join(options.dist, path === '/' ? 'index.html' : path)
    const file = existsSync(wanted) && statSync(wanted).isFile() ? wanted : join(options.dist, 'index.html')
    return new Response(readFileSync(file), { headers: { 'Content-Type': CONTENT_TYPES[extname(file)] ?? 'application/octet-stream' } })
  }

  const server = createServer((incoming, outgoing) => {
    const chunks: Buffer[] = []
    incoming.on('data', (chunk: Buffer) => chunks.push(chunk))
    incoming.on('end', async () => {
      const hasBody = incoming.method !== 'GET' && incoming.method !== 'HEAD' && chunks.length > 0
      const headers = new Headers()
      for (const [name, value] of Object.entries(incoming.headers)) if (typeof value === 'string') headers.set(name, value)
      const request = new Request(`http://127.0.0.1${incoming.url ?? '/'}`, { method: incoming.method ?? 'GET', headers, ...(hasBody ? { body: Buffer.concat(chunks) } : {}) })
      const response = await answer(request)
      outgoing.writeHead(response.status, Object.fromEntries(response.headers))
      outgoing.end(Buffer.from(await response.arrayBuffer()))
    })
  })
  server.listen(0, '127.0.0.1')
  const address = server.address()
  if (address === null || typeof address === 'string') throw new Error('the stand-in parent has no port')
  return { base: `http://127.0.0.1:${address.port}`, patches, commands, updates, stop: () => void server.close() }
}
