// Browser test of the join-share admin page against a TypeScript stand-in of the admin API (CONTRACT section 5).
// Needs Google Chrome (or CHROME_PATH) and `bun install` in frontend/. Run: bun join-share/web/e2e/admin.e2e.ts   (SHOTS_DIR=folder to keep screenshots)
import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import puppeteer, { type Page } from '../../../frontend/node_modules/puppeteer-core'
import { check, finish } from '../../../frontend/e2e/support/check.ts'
import { chromePath, screenshotDir } from '../../../frontend/e2e/support/paths.ts'

const WEB = join(dirname(fileURLToPath(import.meta.url)), '..')
const KEY = 'e2e-admin-key-0123456789'
const RIGHT_CODE = '123456'
const HOSTILE = '<img src=x onerror="window.__pwned=1">evil<script>window.__pwned=2</script>'
const WAIT_MS = 8000
const DESKTOP = { width: 1440, height: 1000 }
const PHONE = { width: 390, height: 900 }

type Pending = { id: string; hostname: string; os: string; cpu: string; share: { cores: number; ram_mb: number; disk_gb: number }; created_at: string; expires_at: string; tries_left: number }
type Peer = { name: string; address: string; public_key: string; os: string; cpu: string; last_handshake_secs_ago: number | null }

// ---- the stand-in of the admin API -------------------------------------------------------------

const inMinutes = (n: number) => new Date(Date.now() + n * 60000).toISOString()
const pendingFor = (id: string, hostname: string, os = 'linux', cpu = 'x86_64'): Pending => ({ id, hostname, os, cpu, share: { cores: 4, ram_mb: 8192, disk_gb: 100 }, created_at: inMinutes(-1), expires_at: inMinutes(14), tries_left: 5 })
const api = {
  supported: [
    { os: 'mac', cpus: [{ cpu: 'arm64', state: 'ready' }, { cpu: 'x86_64', state: 'untested' }] },
    { os: 'windows', cpus: [{ cpu: 'arm64', state: 'soon' }, { cpu: 'x86_64', state: 'soon' }] },
    { os: 'linux', cpus: [{ cpu: 'arm64', state: 'missing' }, { cpu: 'x86_64', state: 'ready' }] },
  ],
  pending: [pendingFor('p1', HOSTILE), pendingFor('p2', 'office-mac', 'mac', 'arm64')] as Pending[],
  peers: [
    { name: 'dgx-lab', address: '10.77.0.2', public_key: 'AbCdEf12', os: 'linux', cpu: 'x86_64', last_handshake_secs_ago: 12 },
    { name: 'new-box', address: '10.77.0.3', public_key: 'ZyXwVu98', os: 'mac', cpu: 'arm64', last_handshake_secs_ago: null },
  ] as Peer[],
  failPending: false,
  nameTaken: false,
  triesLeft: 5,
  linksMade: [] as unknown[],
}

const json = (body: unknown, status = 200) => Response.json(body, { status })

async function admin(request: Request, path: string): Promise<Response> {
  const parts = path.split('/').filter(Boolean)
  if (request.method === 'GET' && path === '/admin/supported') return json(api.supported)
  if (request.method === 'GET' && path === '/admin/pending') return api.failPending ? json({ error: 'wireguard_failed' }, 500) : json(api.pending)
  if (request.method === 'GET' && path === '/admin/peers') return json(api.peers)
  if (request.method === 'POST' && path === '/admin/links') return makeLink(await request.json())
  if (parts[1] === 'pending' && parts[3] === 'approve') return approve(parts[2], await request.json())
  if (parts[1] === 'pending' && parts[3] === 'refuse') return refuse(parts[2])
  if (request.method === 'DELETE' && parts[1] === 'peers') return removePeer(decodeURIComponent(parts[2]))
  return json({ error: 'not_found' }, 404)
}

function makeLink(body: { os: string; cpu: string }): Response {
  api.linksMade.push(body)
  return json({ link: 'abc123', expires_at: inMinutes(15), command: `curl -fsSL "https://join.example.test/j/abc123?os=${body.os}&cpu=${body.cpu}" | sh` })
}

function approve(id: string, body: { code: string; name: string; share: Pending['share'] }): Response {
  const machine = api.pending.find((entry) => entry.id === id)
  if (!machine) return json({ error: 'unknown_pending' }, 404)
  if (api.nameTaken) return json({ error: 'name_taken' }, 409)
  if (body.code !== RIGHT_CODE) {
    api.triesLeft -= 1
    return json({ error: 'wrong_code', tries_left: api.triesLeft }, 403)
  }
  api.pending = api.pending.filter((entry) => entry.id !== id)
  api.peers.push({ name: body.name, address: '10.77.0.9', public_key: 'Qwerty12', os: machine.os, cpu: machine.cpu, last_handshake_secs_ago: null })
  return json({ address: '10.77.0.9' })
}

function refuse(id: string): Response {
  api.pending = api.pending.filter((entry) => entry.id !== id)
  return json({ state: 'refused' })
}

function removePeer(name: string): Response {
  api.peers = api.peers.filter((peer) => peer.name !== name)
  return json({ removed: name })
}

async function route(request: Request): Promise<Response> {
  const path = new URL(request.url).pathname
  if (path === '/') return new Response(Bun.file(join(WEB, 'index.html')), { headers: { 'content-type': 'text/html; charset=utf-8' } })
  if (path === '/app.js') return new Response(Bun.file(join(WEB, 'app.js')), { headers: { 'content-type': 'text/javascript' } })
  if (path === '/style.css') return new Response(Bun.file(join(WEB, 'style.css')), { headers: { 'content-type': 'text/css' } })
  if (request.headers.get('x-admin-key') !== KEY) return json({ error: 'unauthorized' }, 401)
  return admin(request, path)
}

const server = Bun.serve({ port: 0, hostname: '127.0.0.1', fetch: route })
const base = `http://127.0.0.1:${server.port}`

// ---- helpers ----------------------------------------------------------------------------------

const text = (page: Page) => page.evaluate(() => document.body.innerText)
const until = (page: Page, test: () => boolean, ...args: unknown[]) => page.waitForFunction(test as never, { timeout: WAIT_MS }, ...args)
const waitText = (page: Page, wanted: string) => until(page, ((w: string) => document.body.innerText.includes(w)) as never, wanted)

/** Presses the button with this exact label (inside an optional scope selector). */
async function press(page: Page, label: string, scope = 'body'): Promise<void> {
  const done = await page.evaluate((wanted, within) => {
    const found = [...document.querySelectorAll(`${within} button`)].find((b) => (b.textContent ?? '').trim().startsWith(wanted) || b.getAttribute('aria-label') === wanted)
    ;(found as HTMLElement | undefined)?.click()
    return Boolean(found)
  }, label, scope)
  if (!done) throw new Error(`no button "${label}" in ${scope}`)
}

const choiceState = (page: Page, group: string) => page.evaluate((g) => [...document.querySelectorAll(`#${g} button`)].map((b) => ({ text: (b as HTMLElement).innerText.replace(/\s+/g, ' ').trim().toLowerCase(), disabled: (b as HTMLButtonElement).disabled })), group)

async function openWithKey(page: Page): Promise<void> {
  await page.goto('about:blank')
  await page.goto(`${base}/#key=${KEY}`)
  await until(page, () => !document.getElementById('app')!.hidden)
}

async function shot(page: Page, name: string, size: { width: number; height: number }): Promise<void> {
  if (!screenshotDir) return
  mkdirSync(screenshotDir, { recursive: true })
  await page.setViewport(size)
  await page.screenshot({ path: join(screenshotDir, `${name}-${size.width}.png`), fullPage: true })
}

// ---- the test ---------------------------------------------------------------------------------

const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const context = browser.defaultBrowserContext()
await context.overridePermissions(base, ['clipboard-read', 'clipboard-write', 'clipboard-sanitized-write'])
const page = await browser.newPage()
await page.setViewport(DESKTOP)
const problems: string[] = []
page.on('pageerror', (error) => problems.push(String(error)))
page.on('dialog', async (dialog) => { problems.push('dialog: ' + dialog.message()); await dialog.dismiss() })

try {
  // key prompt
  await page.goto(base)
  await until(page, () => !document.getElementById('gate')!.hidden)
  check('without a key the page asks for it and shows nothing else', (await text(page)).includes('Admin key') && (await page.$eval('#app', (n) => (n as HTMLElement).hidden)))
  await page.type('#key-input', 'wrong-key')
  await press(page, 'Continue')
  await waitText(page, 'The admin key is wrong.')
  check('a wrong key gives a plain error and stays on the prompt', !(await page.$eval('#gate', (n) => (n as HTMLElement).hidden)))
  await page.$eval('#key-input', (n) => ((n as HTMLInputElement).value = ''))
  await page.type('#key-input', KEY)
  await press(page, 'Continue')
  await until(page, () => !document.getElementById('app')!.hidden)
  check('the right key opens the page', true)

  // the key from the fragment, kept in memory only
  await openWithKey(page)
  const stored = await page.evaluate(() => JSON.stringify([localStorage.length, sessionStorage.length, document.cookie, location.href]))
  check('a key in the URL fragment opens the page and is removed from the address bar', !stored.includes('key=') && stored.startsWith('[0,0,""'), stored)

  // three buttons and the CPU choices with their states
  check('three system buttons: Mac, Windows, Linux', JSON.stringify((await choiceState(page, 'os-buttons')).map((c) => c.text)) === JSON.stringify(['mac', 'windows', 'linux']))
  check('the make button is off until a CPU is chosen', await page.$eval('#make', (n) => (n as HTMLButtonElement).disabled))
  await press(page, 'Mac', '#os-buttons')
  const mac = await choiceState(page, 'cpu-buttons')
  check('Mac: arm64 is ready, x86_64 is "not tested yet" and still allowed', mac.length === 2 && mac[0].text.includes('ready') && !mac[0].disabled && mac[1].text.includes('not tested yet') && !mac[1].disabled, JSON.stringify(mac))
  await press(page, 'Windows', '#os-buttons')
  const windows = await choiceState(page, 'cpu-buttons')
  check('Windows: both CPUs say "coming soon" and are disabled', windows.every((c) => c.text.includes('coming soon') && c.disabled), JSON.stringify(windows))
  check('Windows: a one-line reason is shown', (await page.$eval('#cpu-note', (n) => n.textContent ?? '')).includes('coming soon'))
  await press(page, 'Linux', '#os-buttons')
  const linux = await choiceState(page, 'cpu-buttons')
  check('Linux: arm64 "no build yet" is disabled with a reason, x86_64 is ready', linux[0].text.includes('no build yet') && linux[0].disabled && linux[1].text.includes('ready') && !linux[1].disabled, JSON.stringify(linux))
  check('Linux: the reason for the missing build is shown', (await page.$eval('#cpu-note', (n) => n.textContent ?? '')).includes('no helper build'))

  // command and copy
  await press(page, 'Intel / AMD', '#cpu-buttons')
  check('after a CPU is chosen the make button works', !(await page.$eval('#make', (n) => (n as HTMLButtonElement).disabled)))
  await press(page, 'Make the command')
  await until(page, () => !document.getElementById('command-box')!.hidden)
  const command = await page.$eval('#command', (n) => n.textContent ?? '')
  check('the command for the choice is shown in the box', command === 'curl -fsSL "https://join.example.test/j/abc123?os=linux&cpu=x86_64" | sh', command)
  check('the stand-in got exactly the chosen pair', JSON.stringify(api.linksMade) === JSON.stringify([{ os: 'linux', cpu: 'x86_64' }]))
  check('the command box is monospace', (await page.$eval('#command', (n) => getComputedStyle(n).fontFamily)).toLowerCase().includes('mono'))
  await page.bringToFront()
  await press(page, 'Copy')
  await waitText(page, 'Copied')
  check('Copy puts the command on the clipboard', (await page.evaluate(() => navigator.clipboard.readText())) === command)

  // hostile host name is only text
  const row = await page.$eval('#pending tbody tr', (tr) => (tr as HTMLElement).innerText)
  check('the pending machine is listed with its host name shown as text', row.includes('<img src=x') && row.includes('<script>'), row)
  check('no element was made from the host name and nothing ran', (await page.$$('#pending img, #pending script')).length === 0 && (await page.evaluate(() => (window as unknown as Record<string, unknown>).__pwned)) === undefined)

  // approve: wrong code, then the right one
  await shot(page, 'admin-full', DESKTOP)
  await shot(page, 'admin-full', PHONE)
  await page.setViewport(DESKTOP)
  const noScroll = await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)
  check('no sideways page scroll at 1440 px', noScroll)
  await page.type('#pending tbody tr:first-child input.code', '000000')
  await press(page, 'Approve', '#pending tbody tr:first-child')
  await waitText(page, 'That code is wrong. 4 tries left.')
  check('a wrong code shows the tries left', true)
  await page.$eval('#pending tbody tr:first-child input.code', (n) => ((n as HTMLInputElement).value = ''))
  await page.type('#pending tbody tr:first-child input.code', RIGHT_CODE)
  await press(page, 'Approve', '#pending tbody tr:first-child')
  await until(page, () => !document.getElementById('pending')!.innerText.includes('evil'))
  check('the right code approves: the machine leaves the waiting list', true)
  const peersText = await page.$eval('#peers', (n) => (n as HTMLElement).innerText)
  check('and appears under joined machines under the name it was given', peersText.includes('10.77.0.9') && api.peers.some((p) => p.address === '10.77.0.9' && /^[a-z0-9._-]+$/.test(p.name)), peersText)

  // name taken and refuse
  api.nameTaken = true
  await page.type('#pending tbody tr:first-child input.code', RIGHT_CODE)
  await press(page, 'Approve', '#pending tbody tr:first-child')
  await waitText(page, 'That name is already used.')
  check('a taken name shows a plain reason', true)
  api.nameTaken = false
  await press(page, 'Refuse', '#pending tbody tr:first-child')
  await waitText(page, 'Nobody is waiting.')
  check('Refuse removes the machine and the empty text shows', api.pending.length === 0)

  // joined machines
  const peers = await page.$eval('#peers', (n) => (n as HTMLElement).innerText)
  check('joined machines show address, system and last handshake', peers.includes('dgx-lab') && peers.includes('10.77.0.2') && peers.includes('12 s ago') && peers.includes('never'), peers)
  await press(page, 'Remove dgx-lab')
  await until(page, () => !document.getElementById('peers')!.innerText.includes('dgx-lab'))
  check('Remove takes the machine out of the list', !api.peers.some((p) => p.name === 'dgx-lab'))
  api.peers = []
  await page.evaluate(() => (window as unknown as { refresh: (force: boolean) => void }).refresh(true))
  await waitText(page, 'No machine has joined yet.')
  check('an empty list says so', true)

  // errors
  api.failPending = true
  await page.evaluate(() => (window as unknown as { refresh: (force: boolean) => void }).refresh(true))
  await waitText(page, 'WireGuard on the hub failed.')
  check('an error from the hub is shown in plain words in place of the list', true)
  api.failPending = false
  server.stop(true)
  await page.evaluate(() => (window as unknown as { refresh: (force: boolean) => void }).refresh(true))
  await waitText(page, 'The hub cannot be reached.')
  check('a hub that is gone is explained', true)

  check('no script error and no dialog on the page', problems.length === 0, problems.join('; '))
} catch (error) {
  check('the test ran to the end', false, String(error instanceof Error ? error.stack : error))
} finally {
  await browser.close()
  server.stop(true)
}
finish()
