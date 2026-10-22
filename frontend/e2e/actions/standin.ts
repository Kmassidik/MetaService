// A stand-in Root for the button tests: it serves the built panel and answers the VM calls slowly, refuses them, or never answers, on command.
// It exists because the real Root answers a start in a few milliseconds, too fast to press a button twice while it works.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { extname, join } from 'node:path'
import { panelDist } from '../support/paths.ts'
import { wait } from '../support/net.ts'
import { createBundleBook } from './bundleBook.ts'
import { createSshKeyBook, type BookAnswer, type SshKeyBook } from './sshKeyBook.ts'

const CSRF = 'test-token'
const TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const BUNDLE_CALL = /^\/api\/machines\/([^/]+)\/bundle\/(install|uninstall)$/
const SETTINGS_CALL = /^\/api\/machines\/([^/]+)\/settings$/
const RETRY_SEGMENT = 'retry'
const MACHINE_PAGE = /^\/api\/machines\/([^/]+)$/
const SSH_KEYS_CALL = /^\/api\/machines\/([^/]+)\/workloads\/([^/]+)\/ssh-keys(?:\/([^/]+))?$/
const VM_CALL =/^\/api\/machines\/([^/]+)\/workloads\/([^/]+)\/(start|stop|delete)$/

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
  /** Every body PATCHed to a machine's settings, in order. */
  settingsPatches: Json[]
  /** The SSH keys of each VM and the switches that change what the answers say. */
  sshKeys: SshKeyBook
  reset: () => void
  close: () => void
}

type Json = Record<string, unknown>

function machine(id: string, workloads: Json[], ruvio: Json): Json {
  return {
    ruvio,
    id, name: id, state: 'online', os: 'linux', arch: 'amd64', ip: '192.168.1.2', cpu_cores: 8, ram_total_mb: 32768, disk_total_gb: 500, free_ram_mb: 20000, free_disk_gb: 400, gpu: [],
    capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: true }, last_seen: new Date().toISOString(),
    settings: { profile: 'custom', labels: [], notes: '', allow_gpu: true }, problems: [], bundle_version: null, agent_version: '0.2.0', agent_build: 'a'.repeat(64),
    update: { available: false, current_build: 'a'.repeat(64), newest_build: 'a'.repeat(64), reason: null }, engine: { name: 'incus', version: '6', ready: true }, workloads,
  }
}

const vm = (id: string, state: string, bundleVersion: string | null = null): Json => ({ id, name: id, kind: 'vm', state, cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: `10.0.0.${id.replace(/\D/g, '')}`, bundle_version: bundleVersion })

/** studio: vm1 has no chat (Install chat) and Ruvio on the machine is old (Update to 0.4.0). mini: vm4 has an old chat (Reinstall chat) and Ruvio is off. */
const fleet = (): Json[] => [
  machine('studio', [vm('vm1', 'running'), vm('vm2', 'stopped'), vm('vm3', 'stopped')], { installed: '0.3.0', pinned: '0.4.0', state: 'outdated' }),
  machine('mini', [vm('vm4', 'running', '0.3.0')], { installed: null, pinned: '0.4.0', state: 'off' }),
]

const order = (type: string, id: string): Json => ({ command: { id, type, machine: 'studio', workload_id: null, state: 'running', created_at: new Date().toISOString(), params: {} } })

const isJson = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value)

/** The JSON a request carries, or an empty object when it carries none. */
async function readJson(request: IncomingMessage): Promise<Json> {
  const chunks: Buffer[] = []
  for await (const chunk of request) chunks.push(Buffer.from(chunk))
  const text = Buffer.concat(chunks).toString('utf8')
  const parsed: unknown = text === '' ? {} : JSON.parse(text)
  return isJson(parsed) ? parsed : {}
}

/** The VM a bundle call is about, or null when it is about the machine itself. */
const workloadOf = (body: Json): string | null => (typeof body.workload === 'string' ? body.workload : null)

const versionOf = (body: Json): string => (typeof body.version === 'string' ? body.version : '')

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
  const settingsPatches: Json[] = []
  const bundles = createBundleBook()
  const sshKeys = createSshKeyBook()

  /** Answers an SSH-keys call from the book: list (GET), add (POST) or remove (DELETE one key). */
  async function sshKeysCall(request: IncomingMessage, response: ServerResponse, match: RegExpExecArray): Promise<void> {
    const [, , vm = '', keyId] = match
    const answered: Record<string, () => Promise<BookAnswer>> = {
      GET: async () => sshKeys.list(vm),
      POST: async () => (keyId === RETRY_SEGMENT ? sshKeys.retry(vm) : sshKeys.add(vm, await readJson(request))),
      DELETE: async () => sshKeys.remove(vm, keyId ?? ''),
    }
    const work = answered[request.method ?? 'GET']
    if (!work) return send(response, 405, { error: 'method not allowed' })
    const result = await work()
    await wait(sshKeys.delayMs)
    send(response, result.status, result.body)
  }

  /** Saves the settings the Environment tab sends (null clears one) and answers with the machine, as the parent does. The ssh_jump setting also changes the command the SSH keys answers give. */
  async function settingsCall(request: IncomingMessage, response: ServerResponse, match: RegExpExecArray): Promise<void> {
    const owner = machines.find((entry) => entry.id === match[1])
    if (!owner || request.method !== 'PATCH') return send(response, 404, { error: { code: 'not_found', message: 'no such machine' } })
    const patch = await readJson(request)
    settingsPatches.push(patch)
    const settings: Json = isJson(owner.settings) ? owner.settings : {}
    for (const [key, value] of Object.entries(patch)) {
      if (key === 'name') continue
      if (value === null) delete settings[key]
      else settings[key] = value
    }
    owner.settings = settings
    if ('ssh_jump' in patch) sshKeys.jumpSetting = typeof patch.ssh_jump === 'string' ? patch.ssh_jump : null
    send(response, 200, owner)
  }

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

  /** Counts the call, then answers it the way the behaviour says (silent, refused, or accepted after the delay, running `accept` first). */
  async function answer(label: string, type: string, response: ServerResponse, accept: () => boolean = () => true): Promise<void> {
    calls.push(label)
    if (behaviour.hang) return
    await wait(behaviour.delayMs)
    if (behaviour.refuseWith !== null) return send(response, 409, { error: { code: 'refused', message: behaviour.refuseWith } })
    if (!accept()) return send(response, 409, { error: { code: 'nothing_to_roll_back_to', message: 'no earlier version was pinned' } })
    send(response, 202, order(type, `order-${calls.length}`))
  }

  const vmCall = (match: RegExpExecArray, response: ServerResponse): Promise<void> => {
    const [, machineId = '', workloadId = '', action = ''] = match
    return answer(`${action} ${workloadId}`, action, response, () => (apply(machineId, workloadId, action), true))
  }

  /** Turns the chat on (pinned version) or off on a VM or on the machine itself, as the helper would once the call is accepted. */
  function applyBundle(machineId: string, workloadId: string | null, on: boolean): boolean {
    const owner = machines.find((entry) => entry.id === machineId)
    const version = on ? bundles.pinned() : null
    const ruvio = owner?.ruvio
    if (workloadId === null && isJson(ruvio)) Object.assign(ruvio, { installed: version, state: on ? 'on' : 'off' })
    const workloads: Json[] = Array.isArray(owner?.workloads) ? owner.workloads : []
    const target = workloads.find((entry) => entry.id === workloadId)
    if (target) target.bundle_version = version
    return true
  }

  async function bundleCall(request: IncomingMessage, response: ServerResponse, match: RegExpExecArray): Promise<void> {
    const [, machineId = '', verb = ''] = match
    const workloadId = workloadOf(await readJson(request))
    return answer(`${verb} ${workloadId ?? machineId}`, `bundle_${verb}`, response, () => applyBundle(machineId, workloadId, verb === 'install'))
  }

  async function pinCall(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const version = versionOf(await readJson(request))
    return answer(`pin ${version}`, 'pin', response, () => bundles.pin(version))
  }

  async function api(request: IncomingMessage, response: ServerResponse, path: string): Promise<void> {
    if (path === '/api/session') return send(response, 200, { username: 'kurnia', csrf_token: CSRF })
    if (path === '/api/auth/status') return send(response, 200, { configured: true, signedIn: true, min_password_length: 8 })
    const posted = request.method === 'POST'
    const keysRoute = SSH_KEYS_CALL.exec(path)
    if (keysRoute) return sshKeysCall(request, response, keysRoute)
    const settingsRoute = SETTINGS_CALL.exec(path)
    if (settingsRoute) return settingsCall(request, response, settingsRoute)
    const call = VM_CALL.exec(path)
    if (call && posted) return vmCall(call, response)
    const bundle = BUNDLE_CALL.exec(path)
    if (bundle && posted) return bundleCall(request, response, bundle)
    if (path === '/api/bundles/pin' && posted) return pinCall(request, response)
    if (path === '/api/bundles/rollback' && posted) return answer('rollback', 'rollback', response, bundles.rollback)
    if (path === '/api/machines') return send(response, 200, { machines })
    const detail = MACHINE_PAGE.exec(path)
    const shown = machines.find((entry) => entry.id === detail?.[1])
    if (shown) return send(response, 200, shown)
    if (path === '/api/commands') return send(response, 200, { commands: [] })
    if (path === '/api/bundles') return send(response, 200, bundles.overview())
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
    settingsPatches,
    sshKeys,
    reset() {
      machines = fleet()
      bundles.reset()
      sshKeys.reset()
      calls.length = 0
      settingsPatches.length = 0
      Object.assign(behaviour, { delayMs: 0, refuseWith: null, hang: false })
    },
    close() {
      server.closeAllConnections()
      server.close()
    },
  }
}
