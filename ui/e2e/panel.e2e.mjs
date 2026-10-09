// End-to-end test of the panel in a real browser against a real Root (test build with the fake sign-in door).
// Needs: the test Root build (root/macos/run-tests.sh builds it), Google Chrome (or CHROME_PATH), and `npm install` in ui/.
import { spawn, spawnSync } from 'node:child_process'
import { chmodSync, mkdtempSync, mkdirSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'
import { networkInterfaces, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import puppeteer from 'puppeteer-core'

const here = dirname(fileURLToPath(import.meta.url))
const repo = resolve(here, '../..')
const binary = join(repo, 'root/macos/.build-fake/debug/metaservice-root')
const agentBinary = join(repo, 'agent/macos/.build/debug/metaservice-agent')
const chrome = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const EMAIL = 'kurnia@example.com'
const XSS = '<img src=x onerror="window.__xss=1">'

const FAKES = join(repo, 'contract/root_tests/fakes')
const SHOTS = process.env.SHOTS_DIR

/** This machine's private /24, so the scan can run against fake nmap and arp programs. Null when there is none. */
function localPrefix() {
  const all = Object.values(networkInterfaces()).flat().filter((entry) => entry.family === 'IPv4' && !entry.internal)
  const mine = all.find((entry) => /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(entry.address))
  return mine ? mine.address.split('.').slice(0, 3).join('.') : null
}

const results = []
const check = (name, ok, detail = '') => {
  results.push(ok)
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !detail ? '' : ': ' + detail}`)
}

async function freePort() {
  return new Promise((done) => {
    const server = createServer().listen(0, '127.0.0.1', () => {
      const { port } = server.address()
      server.close(() => done(port))
    })
  })
}

async function startRoot() {
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-'))
  const bundleDir = join(dir, 'bundles')
  for (const version of ['0.1.0', '0.2.0']) spawnSync('python3', [join(repo, 'bundles/chat/build.py'), '--version', version, '--out', bundleDir])
  const port = await freePort()
  const env = join(dir, 'root.env')
  const prefix = localPrefix()
  const scanLines = prefix ? `SCAN_SUBNET=${prefix}.0/24\nNMAP_PATH=${FAKES}/fake_nmap.py\nARP_PATH=${FAKES}/fake_arp.py\n` : ''
  writeFileSync(env, `ALLOWED_EMAILS=${EMAIL}\n${scanLines}`)
  chmodSync(env, 0o600)
  const base = `http://localhost:${port}`
  const child = spawn(binary, ['--env-file', env, '--db', join(dir, 'db.sqlite3'), '--port', String(port), '--bind', '127.0.0.1',
    '--public-url', base, '--ui-dir', join(repo, 'ui/dist'), '--bundle-dir', bundleDir], { stdio: 'ignore', env: { ...process.env, FAKE_ARP_PREFIX: prefix ?? '' } })
  for (let i = 0; i < 100; i++) {
    if (await fetch(`${base}/health`).then((r) => r.ok, () => false)) return { base, child }
    await new Promise((r) => setTimeout(r, 100))
  }
  throw new Error('Root did not start')
}

/** Sign in as the operator with plain fetch, invite a machine and enroll it as an Agent; returns the machine token. */
let operatorSession = null

async function seed(base) {
  const login = await fetch(`${base}/auth/fake`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: base }, body: JSON.stringify({ email: EMAIL }), redirect: 'manual' })
  const cookie = login.headers.get('set-cookie').split(';')[0]
  const session = await (await fetch(`${base}/api/session`, { headers: { Cookie: cookie } })).json()
  operatorSession = { cookie, csrf: session.csrf_token }
  const write = (path, body) => fetch(`${base}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Cookie: cookie, Origin: base, 'X-CSRF-Token': session.csrf_token }, body: JSON.stringify(body) })
  for (const name of ['dgx-spark', 'mac-mini']) {
    const invite = await (await write('/api/enrollments', { name })).json()
    const enrolled = await (await fetch(`${base}/v1/agents/enroll`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enrollment_token: invite.enrollment_token, name }) })).json()
    const beat = heartbeat(name)
    await fetch(`${base}/v1/agents/heartbeat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${enrolled.machine_token}` }, body: JSON.stringify(beat) })
  }
}

function heartbeat(name) {
  return {
    facts: { os: name === 'mac-mini' ? 'macos' : 'linux', arch: 'aarch64', cpu_cores: 10, ram_total_mb: 32768, disk_total_gb: 1000, free_ram_mb: 20000, free_disk_gb: 700, gpu: [],
      capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false } },
    workloads: [{ id: 'wl-1', name: 'demo', kind: 'vm', state: 'running', cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: XSS, bundle_version: '1.0.0' }],
    bundle_version: '1.0.0',
  }
}

const { base, child } = await startRoot()
/** A real Agent (simulated engine, small known budget) enrolled as "agent-mac" so the Root has someone to send commands to. */
async function startAgent(base, name = 'agent-mac') {
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-agent-'))
  const headers = { 'Content-Type': 'application/json', Cookie: operatorSession.cookie, Origin: base, 'X-CSRF-Token': operatorSession.csrf }
  const invite = await (await fetch(`${base}/api/enrollments`, { method: 'POST', headers, body: JSON.stringify({ name, ip: '127.0.0.1' }) })).json()
  const tokenFile = join(dir, 'enroll.token')
  writeFileSync(tokenFile, invite.enrollment_token)
  chmodSync(tokenFile, 0o600)
  const enrolled = spawnSync(agentBinary, ['enroll', '--root', base.replace('localhost', '127.0.0.1'), '--name', name, '--enrollment-token-file', tokenFile, '--state-dir', dir])
  if (enrolled.status !== 0) throw new Error('agent enroll failed: ' + enrolled.stderr)
  const port = await freePort()
  return spawn(agentBinary, ['run', '--state-dir', dir, '--port', String(port), '--bind', '127.0.0.1', '--engine', 'simulated', '--heartbeat-seconds', '1',
    '--ram-allowance-mb', '16384', '--ram-reserve-mb', '4096', '--disk-allowance-gb', '200', '--disk-reserve-gb', '10',
    '--chat-port', String(await freePort()), '--chat-bind', '127.0.0.1'], { stdio: 'ignore' })
}

async function workloadScenario() {
  const agent = await startAgent(base)
  try {
    await page.waitForFunction(() => document.body.innerText.includes('agent-mac'), { timeout: 20000 })
    await click('New workload')
    await page.waitForSelector('dialog[open] #wl-name')
    await page.type('dialog[open] #wl-name', 'Bad Name')
    check('a bad workload name disables Create and explains', (await page.evaluate(() => document.querySelector('dialog[open] button[type=submit]').disabled)) && (await text()).includes('Use lowercase letters'))
    await page.$eval('dialog[open] #wl-name', (input) => { input.value = ''; input.dispatchEvent(new Event('input')) })
    await page.type('dialog[open] #wl-name', 'build-box')
    await page.evaluate(() => {
      const select = [...document.querySelectorAll('dialog[open] label')].find((l) => l.innerText.startsWith('Machine')).querySelector('select')
      select.value = 'agent-mac'
      select.dispatchEvent(new Event('change', { bubbles: true }))
    })
    await click('Create')
    await page.waitForFunction(() => !document.querySelector('dialog[open]'), { timeout: 10000 })
    await page.waitForFunction(() => /Create\s+build-box[\s\S]*succeeded/.test(document.body.innerText), { timeout: 20000 })
    check('a new workload shows in recent activity as succeeded', true)
    await page.evaluate(() => [...document.querySelectorAll('article')].find((a) => a.innerText.includes('agent-mac')).querySelector('button').click())
    await page.waitForFunction(() => document.body.innerText.includes('build-box'), { timeout: 15000 })
    if (SHOTS) await page.screenshot({ path: join(SHOTS, 'workloads.png'), fullPage: true })
    check('the workload appears under its machine', (await text()).includes('build-box'))
    await click('Stop')
    await page.waitForFunction(() => document.body.innerText.includes('Start'), { timeout: 15000 })
    check('Stop turns the button into Start', true)
    await click('Start')
    await page.waitForFunction(() => [...document.querySelectorAll('button')].some((b) => b.textContent.trim() === 'Stop'), { timeout: 15000 })
    await page.evaluate(() => [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Delete').click())
    await page.waitForSelector('dialog[open]')
    check('delete says a backup is made first', (await text()).includes('makes a backup of it first'))
    await click('Back up and delete')
    await page.waitForFunction(() => !document.body.innerText.includes('build-box') || /Delete\s+[\s\S]*succeeded/.test(document.body.innerText), { timeout: 20000 })
    await page.waitForFunction(() => document.body.innerText.includes('No workloads reported'), { timeout: 20000 })
    check('a deleted workload disappears', true)
    await click('New workload')
    await page.waitForSelector('dialog[open] #wl-name')
    await page.type('dialog[open] #wl-name', 'too-big')
    await page.evaluate(() => {
      const ram = [...document.querySelectorAll('dialog[open] label')].find((l) => l.innerText.startsWith('RAM')).querySelector('input')
      ram.value = '500'
      ram.dispatchEvent(new Event('input', { bubbles: true }))
    })
    await click('Create')
    await page.waitForFunction(() => document.body.innerText.includes('best machine has'), { timeout: 10000 })
    check('a request that fits nowhere shows the numbers', (await text()).includes('needs 512000 MB RAM'))
    await click('Cancel')
  } finally {
    agent.kill()
  }
}

async function bundleScenario() {
  const agent = await startAgent(base, 'chat-mac')
  try {
    await page.waitForFunction(() => document.body.innerText.includes('chat-mac'), { timeout: 20000 })
    await page.waitForFunction(() => document.body.innerText.includes('Chat bundle'))
    const pinTo = async (version) => page.evaluate((v) => [...document.querySelectorAll('section[aria-label="Chat bundle"] li')].find((li) => li.innerText.includes(v)).querySelector('button').click(), version)
    await pinTo('0.1.0')
    await page.waitForFunction(() => /0\.1\.0[\s\S]*pinned/.test(document.body.innerText), { timeout: 10000 })
    check('pinning a version marks it pinned', true)
    await page.evaluate(() => [...document.querySelectorAll('article')].find((a) => a.innerText.includes('chat-mac')).querySelector('button').click())
    await click('Install chat on chat-mac')
    await page.waitForFunction(() => document.body.innerText.includes('chat 0.1.0'), { timeout: 30000 })
    check('installing the chat shows its version on the machine', true)
    await click('Open chat')
    await page.waitForSelector('dialog[open] a')
    check('the chat link opens in a new tab without leaking the referrer', (await page.$eval('dialog[open] a', (a) => a.rel)).includes('noopener'))
    await click('Close')
    await pinTo('0.2.0')
    await page.waitForFunction(() => document.body.innerText.includes('chat 0.2.0'), { timeout: 60000 })
    check('a newer pin upgrades the installed chat by itself', true)
    await click('Roll back to 0.1.0')
    await page.waitForFunction(() => document.body.innerText.includes('chat 0.1.0'), { timeout: 60000 })
    check('a rollback puts the older chat back', true)
    if (SHOTS) await page.screenshot({ path: join(SHOTS, 'bundles.png'), fullPage: true })
  } finally {
    agent.kill()
  }
}

async function scanScenario() {
  await click('Find machines')
  await page.waitForFunction(() => document.body.innerText.includes('Looks at'))
  await click('Scan now')
  await page.waitForFunction(() => document.body.innerText.includes('Unknown device'), { timeout: 20000 })
  const shown = await text()
  check('a scan lists the devices with where they were seen', ['.1', '.40', '.60', '.90'].every((end) => shown.includes(`${localPrefix()}${end}`)) && shown.includes('nmap'))
  check('a device answering on the Agent port is marked', shown.includes('Agent answering'))
  await page.evaluate(() => [...document.querySelectorAll('input[type=checkbox]')].find((box) => box.getAttribute('aria-label')?.endsWith('.60')).click())
  await page.waitForSelector('input[aria-label^="Machine name for"]')
  const suggested = await page.$eval('input[aria-label^="Machine name for"]', (input) => input.value)
  check('picking a device suggests a valid name', /^[a-z0-9][a-z0-9-]*$/.test(suggested), suggested)
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'scan-results.png') })
  await page.$eval('input[aria-label^="Machine name for"]', (input) => { input.value = '' })
  await page.type('input[aria-label^="Machine name for"]', 'dgx-test')
  await click('Create enrollment tokens')
  await page.waitForSelector('dialog[open] code')
  const scanToken = await page.$eval('dialog[open] code', (code) => code.textContent.trim())
  check('adding a found device gives a one-time token', scanToken.length >= 43)
  await click('Done')
  await page.waitForFunction(() => !document.querySelector('dialog[open]'))
  await click('Machines')
}

const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-first-run'] })
let page, text, click
try {
  page = await browser.newPage()
  await page.setViewport({ width: 1280, height: 800 })
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|409)/.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => (window.__csp = (window.__csp ?? 0) + 1 && event.violatedDirective)))
  text = () => page.evaluate(() => document.body.innerText)
  click = async (label) => {
    const handle = await page.evaluateHandle((wanted) => [...(document.querySelector('dialog[open]') ?? document).querySelectorAll('button')].find((b) => b.textContent.trim() === wanted), label)
    await handle.asElement().click()
  }

  await page.goto(base, { waitUntil: 'networkidle0' })
  check('signed-out page shows the sign-in card and no machines', (await text()).includes('MetaService') && !(await text()).includes('dgx-spark'))

  await seed(base)
  await page.evaluate(() => fetch('/auth/fake', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'kurnia@example.com' }) }))
  await page.goto(base, { waitUntil: 'networkidle0' })
  const body = await text()
  check('signed-in page lists the machines', body.includes('dgx-spark') && body.includes('mac-mini') && body.includes(EMAIL))
  check('summary counts the machines and workloads', /MACHINES\s*2/.test(body) && /WORKLOADS\s*2/.test(body), body.slice(0, 120))

  await click('Details')
  await page.waitForFunction(() => document.body.innerText.includes('<img src=x'))
  check('hostile workload text is shown as text, not run', (await page.evaluate(() => window.__xss)) === undefined && (await page.$('img[src="x"]')) === null)

  await click('Add a machine')
  await page.waitForSelector('dialog[open] input')
  await page.type('dialog[open] input', 'Bad Name!')
  check('a bad name disables the button and explains why',
    (await page.evaluate(() => document.querySelector('dialog[open] button[type=submit]').disabled)) && (await text()).includes('Use lowercase letters'))
  await page.$eval('dialog[open] input', (input) => { input.value = '' })
  await page.type('dialog[open] input', 'pc-itx')
  await click('Create token')
  await page.waitForSelector('dialog[open] code')
  const token = await page.$eval('dialog[open] code', (code) => code.textContent.trim())
  check('a valid name shows a one-time token', token.length >= 43, token)
  await click('Done')
  await page.waitForFunction(() => !document.querySelector('dialog[open]'))
  await click('Add a machine')
  await page.waitForSelector('dialog[open] input')
  check('the token is not shown again', !(await text()).includes(token))
  await click('Cancel')

  await page.evaluate(() => [...document.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === 'Remove mac-mini').click())
  await page.waitForSelector('dialog[open]')
  check('remove asks first and says what happens', (await text()).includes('Its VMs keep running'))
  await click('Remove machine')
  await page.waitForFunction(() => !document.body.innerText.includes('mac-mini'), { timeout: 5000 })
  check('a removed machine disappears', !(await text()).includes('mac-mini'))

  await workloadScenario()
  await bundleScenario()
  if (localPrefix()) await scanScenario()

  await page.setViewport({ width: 390, height: 844 })
  await page.reload({ waitUntil: 'networkidle0' })
  check('no sideways scrolling on a phone', await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))

  await click('Sign out')
  await page.waitForFunction(() => document.body.innerText.includes('Google sign-in'), { timeout: 10000 })
  check('signing out returns to the sign-in page', !(await text()).includes('dgx-spark'))
  check('no script errors and no policy violations', errors.length === 0 && (await page.evaluate(() => window.__csp)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  child.kill()
}
const failed = results.filter((ok) => !ok).length
console.log(`\n${results.length - failed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
