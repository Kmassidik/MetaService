// A stand-in parent with a small hub behind /api/join-share/*: it serves the built panel, answers the sign-in calls, and plays the hub
// (supported table, links, waiting machines with a code, joined machines). The hub's status codes and error words are passed through as the parent does.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { extname, join } from 'node:path'
import { panelDist } from '../support/paths.ts'

export const CSRF = 'test-token'
export const RIGHT_CODE = '123456'
const TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
const SHARE_CALL = /^\/api\/join-share\/(supported|links|pending|peers)(?:\/([^/]+)(?:\/(approve|refuse))?)?$/
const QUARTER_HOUR_MS = 15 * 60_000

type Json = Record<string, unknown>
export type HubMode = 'ok' | 'not_configured' | 'hub_unreachable'

export interface Hub {
  base: string
  /** How the hub behaves: working, not set up on the parent, or not answering. */
  mode: HubMode
  pending: Json[]
  peers: Json[]
  /** The body of every approve that reached the hub, in order. */
  approvals: Json[]
  /** The addresses of every call that reached the hub, as "GET pending". */
  calls: string[]
  addPending: (id: string, hostname: string) => void
  close: () => void
}

const SUPPORTED = [
  { os: 'mac', cpus: [{ cpu: 'arm64', state: 'ready' }, { cpu: 'x86_64', state: 'untested' }] },
  { os: 'windows', cpus: [{ cpu: 'arm64', state: 'missing' }, { cpu: 'x86_64', state: 'soon' }] },
  { os: 'linux', cpus: [{ cpu: 'arm64', state: 'missing' }, { cpu: 'x86_64', state: 'ready' }] },
]

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

const pendingRow = (id: string, hostname: string): Json => ({
  id, hostname, os: 'mac', cpu: 'arm64', share: { cores: 4, ram_mb: 8192, disk_gb: 100 },
  created_at: new Date().toISOString(), expires_at: new Date(Date.now() + QUARTER_HOUR_MS).toISOString(), tries_left: 5,
})

const peerRow = (name: string, secsAgo: number | null): Json => ({ name, address: '10.77.0.9', public_key: 'AbCdEfGh', os: 'linux', cpu: 'x86_64', last_handshake_secs_ago: secsAgo })

export async function startHub(): Promise<Hub> {
  const hub: Hub = {
    base: '', mode: 'ok', pending: [], peers: [peerRow('busy-box', 42), peerRow('old-pc', null)], approvals: [], calls: [],
    addPending: (id, hostname) => void hub.pending.push(pendingRow(id, hostname)),
    close: () => {},
  }
  hub.addPending('p1', 'Far Mac')
  hub.addPending('p2', '<img src=x onerror="window.__pwned=1">')
  hub.addPending('p3', 'busy-box')

  async function share(request: IncomingMessage, response: ServerResponse, path: string) {
    const match = SHARE_CALL.exec(path)
    if (!match) return send(response, 404, {})
    if (hub.mode === 'not_configured') return send(response, 404, { error: 'not_configured' })
    if (hub.mode === 'hub_unreachable') return send(response, 502, { error: 'hub_unreachable' })
    const [, route = '', id = '', action = ''] = match
    const method = request.method ?? 'GET'
    hub.calls.push(`${method} ${route}${id ? '/' + id : ''}${action ? '/' + action : ''}`)
    if (method !== 'GET' && request.headers['x-csrf-token'] !== CSRF) return send(response, 403, { error: { code: 'forbidden', message: 'missing or wrong CSRF token' } })
    if (route === 'supported') return send(response, 200, SUPPORTED)
    if (route === 'pending' && !id) return send(response, 200, hub.pending)
    if (route === 'peers' && !id) return send(response, 200, hub.peers)
    if (route === 'links') {
      const input = await bodyOf(request)
      return send(response, 200, { link: 'abc', expires_at: new Date(Date.now() + 3_600_000).toISOString(), command: `curl -fsSL "https://hub.example/j/abc?os=${String(input.os)}&cpu=${String(input.cpu)}" | sh` })
    }
    if (route === 'pending' && action) return pendingAction(request, response, id, action)
    if (route === 'peers' && method === 'DELETE') return removePeer(response, id)
    return send(response, 404, {})
  }

  async function pendingAction(request: IncomingMessage, response: ServerResponse, id: string, action: string) {
    const found = hub.pending.find((row) => row.id === id)
    if (!found) return send(response, 404, { error: 'unknown_pending' })
    if (action === 'refuse') {
      hub.pending.splice(hub.pending.indexOf(found), 1)
      return send(response, 200, { state: 'refused' })
    }
    const input = await bodyOf(request)
    hub.approvals.push(input)
    if (input.code !== RIGHT_CODE) {
      found.tries_left = Number(found.tries_left) - 1
      return send(response, 403, { error: 'wrong_code', tries_left: found.tries_left })
    }
    if (hub.peers.some((peer) => peer.name === input.name)) return send(response, 409, { error: 'name_taken' })
    hub.pending.splice(hub.pending.indexOf(found), 1)
    hub.peers.push(peerRow(String(input.name), null))
    return send(response, 200, { address: '10.77.0.2' })
  }

  function removePeer(response: ServerResponse, name: string) {
    const found = hub.peers.find((peer) => peer.name === name)
    if (!found) return send(response, 404, { error: 'unknown_peer' })
    hub.peers.splice(hub.peers.indexOf(found), 1)
    return send(response, 200, { removed: name })
  }

  const server: Server = createServer(async (request, response) => {
    const path = new URL(request.url ?? '/', 'http://stand-in').pathname
    if (path.startsWith('/api/join-share/')) return share(request, response, path)
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
  hub.base = `http://127.0.0.1:${address.port}`
  hub.close = () => {
    server.closeAllConnections()
    server.close()
  }
  return hub
}
