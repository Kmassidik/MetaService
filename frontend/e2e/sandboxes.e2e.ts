// Unified Sandboxes navigation and lifecycle: one sidebar entry, three tabs, key creation,
// sandbox create/pause/resume/kill, and usage. Runs against a stand-in parent; no helper is needed.
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { extname, join } from 'node:path'
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const CSRF = 'test-token'
const TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2' }
type Json = Record<string, unknown>

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

async function body(request: IncomingMessage): Promise<Json> {
  const chunks: Buffer[] = []
  for await (const chunk of request) chunks.push(Buffer.from(chunk))
  const text = Buffer.concat(chunks).toString('utf8')
  return text ? JSON.parse(text) as Json : {}
}

function sandbox(id: string, state: string): Json {
  return { id, team: 'team-one', team_name: 'team-one', machine: 'test-box', state, template: 'base', vcpu: 1, ram_mb: 2048, disk_mb: 20480, created_at: new Date().toISOString(), end_at: new Date(Date.now() + 3_600_000).toISOString() }
}

const keys: Json[] = []
const sandboxes: Json[] = []
const server = createServer(async (request, response) => {
  const path = new URL(request.url ?? '/', 'http://stand-in').pathname
  if (!path.startsWith('/api/') && !path.startsWith('/v2/')) return serveFile(path, response)
  if (path === '/api/session') return send(response, 200, { username: 'kurnia', csrf_token: CSRF })
  if (path === '/api/auth/status') return send(response, 200, { configured: true, signedIn: true, min_password_length: 8 })
  if (path === '/api/machines') return send(response, 200, { machines: [] })
  if (path === '/api/commands') return send(response, 200, { commands: [] })
  if (path === '/api/bundles') return send(response, 200, { pinned: null, bundles: [] })
  if (path === '/api/brain') return send(response, 200, { configured: true, usage: [] })
  if (path === '/api/remote/machines') return send(response, 200, { machines: [] })
  if (path === '/api/sandboxes/keys') {
    if (request.method === 'GET') return send(response, 200, { keys })
    if (request.method === 'POST') {
      const input = await body(request)
      const teamName = typeof input.team_name === 'string' && input.team_name ? input.team_name : 'our-apps'
      const made = { id: 'key-1', team: 'team-one', team_name: teamName, prefix: 'msb_ab12cd34', key: 'msb_ab12cd34_e2e-secret', created_at: new Date().toISOString() }
      keys.push({ ...made, key: undefined, last_used_at: null, revoked_at: null })
      return send(response, 201, made)
    }
  }
  const keyMatch = /^\/api\/sandboxes\/keys\/([^/]+)$/.exec(path)
  if (keyMatch && request.method === 'DELETE') {
    const found = keys.find((entry) => entry.id === keyMatch[1])
    if (found) found.revoked_at = new Date().toISOString()
    return send(response, 204, {})
  }
  if (path === '/api/sandboxes' && request.method === 'GET') return send(response, 200, { sandboxes })
  if (path === '/v2/sandboxes' && request.method === 'POST') {
    const made = sandbox('sb-e2e-01', 'running')
    sandboxes.push(made)
    return send(response, 201, made)
  }
  const actionMatch = /^\/api\/sandboxes\/([^/]+)\/(kill|pause|connect)$/.exec(path)
  if (actionMatch && request.method === 'POST') {
    const [, id, action] = actionMatch
    const found = sandboxes.find((entry) => entry.id === id)
    if (!found) return send(response, 404, { error: { code: 'not_found', message: 'no such sandbox' } })
    if (action === 'kill') {
      sandboxes.splice(sandboxes.indexOf(found), 1)
      return send(response, 204, {})
    }
    found.state = action === 'pause' ? 'paused' : 'running'
    return send(response, 200, found)
  }
  if (path === '/api/sandboxes/usage') {
    const used = sandboxes.length === 0
    return send(response, 200, { days: 7, starts_at: '2026-10-21T00:00:00Z', ends_at: '2026-10-28T00:00:00Z', teams: [{ team: 'team-one', team_name: 'team-one', sandboxes: used ? 1 : 0, seconds: used ? 12 : 0, vcpu_seconds: used ? 12 : 0, ram_mb_seconds: used ? 24_576 : 0 }] })
  }
  return send(response, 404, { error: { code: 'not_found', message: path } })
})

// This TypeScript target has no Promise.withResolvers yet.
const listening = new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
await listening
const address = server.address()
if (address === null || typeof address === 'string') throw new Error('no stand-in port')
const base = `http://127.0.0.1:${address.port}`
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1280, height: 850 })
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))

  const b = browse(page)
  await page.goto(`${base}/#/sandboxes/keys`, { waitUntil: 'networkidle0' })

  await b.click('Make a key')
  await b.until(() => document.querySelector('[data-testid="new-key-text"]') !== null)
  const newKey = await b.run(() => document.querySelector('[data-testid="new-key-text"]')?.textContent ?? '')
  check('the new key is shown once', newKey.startsWith('msb_ab12cd34_'), newKey)
  await b.click('Done, I have it')
  await b.click('Revoke')
  await b.click('Revoke key')
  await b.until(() => /revoked/i.test(document.body.innerText))
  check('a key can be made and revoked', true)

  const created = await page.evaluate(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v2/sandboxes`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ template: 'base', team: 'team-one' }) })
    return response.status
  }, base)
  check('a sandbox is created through the API', created === 201, String(created))
  await b.go('#/sandboxes')
  await b.until(() => document.body.innerText.includes('sb-e2e-01'))
  await b.click('Pause')
  await b.until(() => document.body.innerText.includes('Paused'))
  const resumed = await page.evaluate(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/sandboxes/sb-e2e-01/connect`, { method: 'POST' })
    return response.status
  }, base)
  check('a paused sandbox resumes through connect', resumed === 200, String(resumed))
  await b.until(() => !document.body.innerText.includes('Pausing…') && !document.body.innerText.includes('Resuming…'))
  await b.click('Kill')
  await b.until(() => [...document.querySelectorAll('dialog[open] button')].some(button => button.textContent?.trim() === 'Kill sandbox'))
  await b.click('Kill sandbox')
  await b.until(() => document.body.innerText.includes('No sandboxes are running'))

  await b.go('#/sandboxes/usage')
  await b.until(() => document.body.innerText.includes('team-one') && document.body.innerText.includes('12'))
  const usageText = await b.text()
  check('finished sandbox usage includes seconds, vCPU and memory', usageText.includes('12') && usageText.includes('24,576'), usageText.slice(-500))

  await b.go('#/keys')
  check('the old keys address opens the API keys tab', await b.run(() => document.querySelector('#sandbox-tab-keys')?.getAttribute('aria-selected') === 'true'))
  const navText = await b.run(() => document.querySelector<HTMLElement>('aside.side')?.innerText ?? '')
  check('the sidebar has one Sandboxes entry', (navText.match(/Sandboxes/g) ?? []).length === 1, navText)
  check('separate API keys and Sandbox usage links are gone', !navText.includes('API keys') && !navText.includes('Sandbox usage'), navText)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  server.closeAllConnections()
  server.close()
}
finish()
