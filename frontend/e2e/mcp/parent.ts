// A stand-in parent for the AI access section: it serves the built panel, answers the sign-in calls, and plays /api/mcp/*
// (info, tokens, approvals, activity). Every write must carry the CSRF header, as the real parent demands.
import { randomBytes } from 'node:crypto'
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { extname, join } from 'node:path'
import { panelDist } from '../support/paths.ts'

export const CSRF = 'test-token'
export const ENDPOINT = 'https://meta.example.test/mcp'
const TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const MCP_CALL = /^\/api\/mcp\/(info|tokens|approvals|activity)(?:\/([^/]+)(?:\/(approve|deny))?)?$/
const QUOTAS = { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10 }
const HOUR_MS = 3_600_000
const DAY_MS = 24 * HOUR_MS

type Json = Record<string, unknown>
/** ok: working; old: a parent without AI access (404); broken: answers 500. */
export type ParentMode = 'ok' | 'old' | 'broken'

export interface Parent {
  base: string
  mode: ParentMode
  tokens: Json[]
  pending: Json[]
  recent: Json[]
  activity: Json[]
  /** The token text of the last token made: the only time it is ever sent. */
  lastSecret: string
  /** The body of every token made. */
  made: Json[]
  /** Every call that reached /api/mcp, as "GET approvals". */
  calls: string[]
  /** Writes that came without the CSRF header. */
  withoutCsrf: string[]
  addPending: (id: string, tokenName: string, kind: string, params: Json) => void
  close: () => void
}

function send(response: ServerResponse, status: number, body: unknown) {
  response.writeHead(status, { 'Content-Type': 'application/json' })
  response.end(JSON.stringify(body))
}

function serveFile(path: string, response: ServerResponse) {
  const wanted = join(panelDist, path === '/' ? 'index.html' : path)
  const file = existsSync(wanted) && statSync(wanted).isFile() ? wanted : join(panelDist, 'index.html')
  response.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' })
  response.end(readFileSync(file))
}

async function bodyOf(request: IncomingMessage): Promise<Json> {
  const chunks: Buffer[] = []
  for await (const chunk of request) chunks.push(Buffer.from(chunk))
  const text = Buffer.concat(chunks).toString('utf8')
  return text ? (JSON.parse(text) as Json) : {}
}

const tokenRow = (id: string, name: string, more: Json = {}): Json => ({
  id, name, prefix: randomBytes(4).toString('hex'), scopes: ['read', 'create'], quotas: QUOTAS, auto_approve: false,
  created_at: new Date(Date.now() - DAY_MS).toISOString(), expires_at: new Date(Date.now() + 89 * DAY_MS).toISOString(), last_used_at: null, revoked_at: null, ...more,
})

const activityRow = (minutesAgo: number, token: string, tool: string, target: string | null, status: string): Json => ({
  at: new Date(Date.now() - minutesAgo * 60_000).toISOString(), actor: `mcp:${token}`, action: `mcp.${tool}`, target, status,
})

export async function startParent(): Promise<Parent> {
  const parent: Parent = {
    base: '', mode: 'ok', tokens: [tokenRow('t1', 'my laptop', { last_used_at: new Date(Date.now() - 5 * 60_000).toISOString() })], pending: [], recent: [],
    activity: [activityRow(2, 'my laptop', 'list_vms', null, 'ok'), activityRow(9, 'my laptop', 'create_vm', 'rtx-pc/box', 'ok')],
    lastSecret: '', made: [], calls: [], withoutCsrf: [],
    addPending: (id, tokenName, kind, params) => void parent.pending.push({ id, token_name: tokenName, kind, params, state: 'pending_approval', created_at: new Date().toISOString(), expires_at: new Date(Date.now() + DAY_MS).toISOString(), decided_by: null, decided_at: null }),
    close: () => {},
  }
  parent.addPending('r1', 'my laptop', 'create', { machine_name: 'rtx-pc', size: 'medium', gpu_memory_gb: 4 })
  parent.addPending('r2', '<img src=x onerror="window.__pwned=1">', 'delete', { machine_name: 'rtx-pc', vm_name: '<b>victim</b>' })

  function decide(response: ServerResponse, id: string, verdict: string) {
    const found = parent.pending.find((row) => row.id === id)
    if (!found) return send(response, 409, { error: { code: 'not_pending', message: 'This request was already decided.' } })
    parent.pending.splice(parent.pending.indexOf(found), 1)
    parent.recent.unshift({ ...found, state: verdict === 'approve' ? 'done' : 'denied', decided_by: 'kurnia', decided_at: new Date().toISOString() })
    return send(response, 200, { state: verdict })
  }

  async function makeToken(request: IncomingMessage, response: ServerResponse) {
    const input = await bodyOf(request)
    parent.made.push(input)
    parent.lastSecret = `msk_${randomBytes(32).toString('base64url')}`
    parent.tokens.push(tokenRow(`t${parent.tokens.length + 1}`, String(input.name), { scopes: input.scopes, quotas: input.quotas, auto_approve: input.auto_approve }))
    return send(response, 201, { token: parent.lastSecret, id: `t${parent.tokens.length}` })
  }

  async function mcp(request: IncomingMessage, response: ServerResponse, path: string) {
    const match = MCP_CALL.exec(path)
    if (!match || parent.mode === 'old') return send(response, 404, { error: { code: 'not_found', message: path } })
    if (parent.mode === 'broken') return send(response, 500, { error: { code: 'internal', message: 'The AI access store could not be read.' } })
    const [, route = '', id = '', action = ''] = match
    const method = request.method ?? 'GET'
    parent.calls.push(`${method} ${route}`)
    if (method !== 'GET' && request.headers['x-csrf-token'] !== CSRF) {
      parent.withoutCsrf.push(`${method} ${path}`)
      return send(response, 403, { error: { code: 'forbidden', message: 'missing or wrong CSRF token' } })
    }
    if (route === 'info') return send(response, 200, { endpoint: ENDPOINT, protocol_versions: ['2025-06-18'], tools: ['list_machines', 'machine_capacity', 'list_vms', 'vm_status', 'create_vm', 'start_vm', 'stop_vm', 'delete_vm', 'get_request'], defaults: { scopes: ['read', 'create'], expires_in_days: 90, quotas: { ...QUOTAS, gpu_memory_gb: 8 } } })
    if (route === 'tokens' && method === 'GET') return send(response, 200, { tokens: parent.tokens })
    if (route === 'tokens' && method === 'POST') return makeToken(request, response)
    if (route === 'tokens' && method === 'DELETE') return revoke(response, id)
    if (route === 'approvals' && action) return decide(response, id, action)
    if (route === 'approvals') return send(response, 200, { pending: parent.pending, recent: parent.recent })
    return send(response, 200, { activity: parent.activity })
  }

  function revoke(response: ServerResponse, id: string) {
    const found = parent.tokens.find((row) => row.id === id)
    if (!found) return send(response, 404, { error: { code: 'unknown_token', message: 'No such token.' } })
    found.revoked_at = new Date().toISOString()
    response.writeHead(204)
    response.end()
  }

  const server: Server = createServer(async (request, response) => {
    const path = new URL(request.url ?? '/', 'http://stand-in').pathname
    if (path.startsWith('/api/mcp/')) return mcp(request, response, path)
    if (!path.startsWith('/api/')) return serveFile(path, response)
    if (path === '/api/session') return send(response, 200, { username: 'kurnia', csrf_token: CSRF })
    if (path === '/api/auth/status') return send(response, 200, { configured: true, signedIn: true, min_password_length: 8 })
    if (path === '/api/machines') return send(response, 200, { machines: [] })
    if (path === '/api/commands') return send(response, 200, { commands: [] })
    if (path === '/api/bundles') return send(response, 200, { pinned: null, bundles: [] })
    if (path === '/api/brain') return send(response, 200, { configured: true, usage: [] })
    if (path === '/api/remote/machines') return send(response, 200, { machines: [] })
    return send(response, 404, { error: { code: 'not_found', message: path } })
  })
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (address === null || typeof address === 'string') throw new Error('no stand-in port')
  parent.base = `http://127.0.0.1:${address.port}`
  parent.close = () => {
    server.closeAllConnections()
    server.close()
  }
  return parent
}
