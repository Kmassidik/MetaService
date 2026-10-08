// End-to-end test of the panel in a real browser against a real Root (test build with the fake sign-in door).
// Needs: the test Root build (root/macos/run-tests.sh builds it), Google Chrome (or CHROME_PATH), and `npm install` in ui/.
import { spawn } from 'node:child_process'
import { chmodSync, mkdtempSync, mkdirSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import puppeteer from 'puppeteer-core'

const here = dirname(fileURLToPath(import.meta.url))
const repo = resolve(here, '../..')
const binary = join(repo, 'root/macos/.build-fake/debug/metaservice-root')
const chrome = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const EMAIL = 'kurnia@example.com'
const XSS = '<img src=x onerror="window.__xss=1">'

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
  const port = await freePort()
  const env = join(dir, 'root.env')
  writeFileSync(env, `ALLOWED_EMAILS=${EMAIL}\n`)
  chmodSync(env, 0o600)
  const base = `http://localhost:${port}`
  const child = spawn(binary, ['--env-file', env, '--db', join(dir, 'db.sqlite3'), '--port', String(port), '--bind', '127.0.0.1',
    '--public-url', base, '--ui-dir', join(repo, 'ui/dist')], { stdio: 'ignore' })
  for (let i = 0; i < 100; i++) {
    if (await fetch(`${base}/health`).then((r) => r.ok, () => false)) return { base, child }
    await new Promise((r) => setTimeout(r, 100))
  }
  throw new Error('Root did not start')
}

/** Sign in as the operator with plain fetch, invite a machine and enroll it as an Agent; returns the machine token. */
async function seed(base) {
  const login = await fetch(`${base}/auth/fake`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: base }, body: JSON.stringify({ email: EMAIL }), redirect: 'manual' })
  const cookie = login.headers.get('set-cookie').split(';')[0]
  const session = await (await fetch(`${base}/api/session`, { headers: { Cookie: cookie } })).json()
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
const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  page.on('console', (message) => message.type() === 'error' && !message.text().includes('401') && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => (window.__csp = (window.__csp ?? 0) + 1 && event.violatedDirective)))
  const text = () => page.evaluate(() => document.body.innerText)
  const click = async (label) => {
    const handle = await page.evaluateHandle((wanted) => [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === wanted), label)
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

  await page.setViewport({ width: 390, height: 844 })
  await page.reload({ waitUntil: 'networkidle0' })
  check('no sideways scrolling on a phone', await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))

  await click('Sign out')
  await page.waitForFunction(() => !document.body.innerText.includes('dgx-spark'))
  check('signing out returns to the sign-in page', (await text()).includes('Google sign-in'))
  check('no script errors and no policy violations', errors.length === 0 && (await page.evaluate(() => window.__csp)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  child.kill()
}
const failed = results.filter((ok) => !ok).length
console.log(`\n${results.length - failed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
