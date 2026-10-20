// End-to-end test of Connect (add another computer, steps one and two) in a real browser against a real Root and a real OpenSSH server on loopback.
// Needs: the Root build and the macOS Agent build (`swift build`), Google Chrome (or CHROME_PATH), /usr/sbin/sshd, and `npm install` in frontend/.
import { spawn, spawnSync } from 'node:child_process'
import { appendFileSync, chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'
import { tmpdir, userInfo } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import puppeteer from 'puppeteer-core'

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const binary = join(repo, 'control-plane/arm64/.build/debug/metaservice-root')
const agentBinary = join(repo, 'agent/macos/.build/debug/metaservice-agent')
const chrome = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const SHOTS = process.env.SHOTS_DIR
const ADMIN = { username: 'admin', password: 'correct horse battery' }
const SETUP_TOKEN = 'e2e-setup-token-0123456789abcdef'

const results = []
const check = (name, ok, detail = '') => {
  results.push(ok)
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !detail ? '' : ': ' + detail}`)
}

const freePort = () => new Promise((done) => { const server = createServer().listen(0, '127.0.0.1', () => { const { port } = server.address(); server.close(() => done(port)) }) })
const wait = (ms) => new Promise((done) => setTimeout(done, ms))

/** A real sshd as this user on loopback, with a key-only login. */
async function startSshd() {
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-sshd-'))
  spawnSync('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(dir, 'host')])
  const authorized = join(dir, 'authorized_keys')
  writeFileSync(authorized, '')
  chmodSync(authorized, 0o600)
  const port = await freePort()
  writeFileSync(join(dir, 'config'), [`Port ${port}`, 'ListenAddress 127.0.0.1', `HostKey ${dir}/host`, `AuthorizedKeysFile ${authorized}`, 'PasswordAuthentication no', 'KbdInteractiveAuthentication no',
    'PubkeyAuthentication yes', 'UsePAM no', 'StrictModes no', `PidFile ${dir}/pid`, 'LogLevel ERROR'].join('\n') + '\n')
  // OpenSSH 9.8+ ignores an address for a while after failed logins; the test must not depend on that, so it is switched off where the server knows the setting.
  appendFileSync(join(dir, 'config'), 'PerSourcePenalties no\n')
  if (spawnSync('/usr/sbin/sshd', ['-t', '-f', join(dir, 'config')]).status !== 0) writeFileSync(join(dir, 'config'), readFileSync(join(dir, 'config'), 'utf8').replace('PerSourcePenalties no\n', ''))
  const child = spawn('/usr/sbin/sshd', ['-D', '-e', '-f', join(dir, 'config')], { stdio: 'ignore' })
  await wait(800)
  const fingerprint = spawnSync('ssh-keygen', ['-lf', join(dir, 'host.pub')]).stdout.toString().split(' ')[1]
  return { port, child, authorized, fingerprint }
}

async function startRoot() {
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-'))
  const env = join(dir, 'root.env')
  writeFileSync(env, `ROOT_SETUP_TOKEN=${SETUP_TOKEN}\n`)
  chmodSync(env, 0o600)
  const port = await freePort()
  const base = `http://localhost:${port}`
  const child = spawn(binary, ['--env-file', env, '--db', join(dir, 'db.sqlite3'), '--port', String(port), '--bind', '127.0.0.1', '--agent-port', String(await freePort()), '--agent-bind', '127.0.0.1',
    '--agent-binary', agentBinary, '--public-url', base, '--ui-dir', join(repo, 'frontend/dist'), '--remote-allow-loopback', 'yes', '--remote-engine', 'simulated', '--remote-tries', '30'], { stdio: ['ignore', 'ignore', process.env.ROOT_LOG ? 'inherit' : 'ignore'] })
  for (let i = 0; i < 100; i++) {
    if (await fetch(`${base}/health`).then((r) => r.ok, () => false)) return { base, child }
    await wait(100)
  }
  throw new Error('Root did not start')
}

/** The admin is made through the API, so the page only has to sign in; then the parent's public key goes into the test server's authorized keys. */
async function prepare(base, sshd) {
  const made = await fetch(`${base}/api/auth/setup`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: base },
    body: JSON.stringify({ ...ADMIN, confirm: ADMIN.password, setup_token: SETUP_TOKEN }) })
  const cookie = made.headers.get('set-cookie').split(';')[0]
  const key = (await (await fetch(`${base}/api/remote/key`, { headers: { Cookie: cookie } })).json()).public_key
  appendFileSync(sshd.authorized, key + '\n')
  return key
}

const sshd = await startSshd()
const root = await startRoot()
const publicKey = await prepare(root.base, sshd)
const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1280, height: 800 })
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|422|502)/.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => (window.__csp = event.violatedDirective)))
  const text = () => page.evaluate(() => document.body.innerText)
  const dialog = () => page.evaluate(() => document.querySelector('dialog[open]')?.innerText ?? '')
  const click = async (label) => {
    const handle = await page.evaluateHandle((wanted) => [...(document.querySelector('dialog[open]') ?? document).querySelectorAll('button')].find((b) => b.textContent.trim() === wanted), label)
    await handle.asElement().click()
  }
  const type = async (selector, value) => {
    await page.$eval(selector, (input) => { input.value = ''; input.dispatchEvent(new Event('input', { bubbles: true })) })
    await page.type(selector, value)
  }
  const waitForDialog = async (pattern, timeout = 20000) => {
    try {
      await page.waitForFunction((source) => new RegExp(source, 'i').test(document.querySelector('dialog[open]')?.innerText ?? ''), { timeout }, pattern.source)
    } catch {
      throw new Error(`waiting for ${pattern} failed; the dialog says: ${(await dialog()).replace(/\s+/g, ' ').slice(-500)}`)
    }
  }

  await page.goto(root.base, { waitUntil: 'networkidle0' })
  await page.type('input[name=username]', ADMIN.username)
  await page.type('input[name=password]', ADMIN.password)
  await click('Sign in')
  await page.waitForFunction(() => document.body.innerText.includes('No machines yet'), { timeout: 10000 })
  await page.goto(`${root.base}/#/machines/connect`)
  await page.waitForFunction(() => [...document.querySelectorAll('button')].some((b) => b.textContent.includes('Connect a computer')), { timeout: 10000 })

  await click('Connect a computer')
  await page.waitForSelector('dialog[open] #connect-host')
  check('the Connect dialog opens on step 1 and says it only looks', /Connect a computer/.test(await dialog()) && /nothing is installed or changed/i.test(await dialog()))
  check('Look at it is disabled until an address is typed', await page.evaluate(() => [...document.querySelectorAll('dialog[open] button')].find((b) => b.textContent.trim() === 'Look at it').disabled))
  await type('#connect-host', '-oProxyCommand=evil')
  check('an address that could be an ssh option is refused on the spot', /address/i.test(await dialog()) && await page.evaluate(() => [...document.querySelectorAll('dialog[open] button')].find((b) => b.textContent.trim() === 'Look at it').disabled))

  await type('#connect-host', '127.0.0.1')
  await type('#connect-port', '1')
  await click('Look at it')
  await waitForDialog(/did not show an SSH host key|cannot reach that computer/)
  check('a port with no SSH gives a plain message and stays on step 1', /did not show an SSH host key/i.test(await dialog()) && (await page.$('#connect-host')) !== null)

  // The path to step 3, with the parent's key: used twice, so it is a function.
  const reachResult = async () => {
    await type('#connect-host', '127.0.0.1')
    await type('#connect-port', String(sshd.port))
    await click('Look at it')
    await waitForDialog(/Is this the computer you mean/)
    await type('#connect-user', userInfo().username)
    await page.evaluate(() => [...document.querySelectorAll('dialog[open] input[type=radio]')][1].click())
    await page.waitForFunction(() => /ssh-ed25519/.test(document.querySelector('dialog[open] [aria-label="The parent\'s public key"]')?.textContent ?? ''), { timeout: 10000 })
    await click('Yes, log in and check')
    await waitForDialog(/Looks good/)
  }

  await type('#connect-port', String(sshd.port))
  await click('Look at it')
  await waitForDialog(/Is this the computer you mean/)
  const shown = (await page.$eval('dialog[open] [aria-label="Host key fingerprint"]', (node) => node.textContent)).replace(/\s+/g, '')
  check('step 2 shows the server\'s real host key fingerprint', shown === sshd.fingerprint, `${shown} vs ${sshd.fingerprint}`)
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'connect-confirm.png') })

  await type('#connect-user', userInfo().username)
  check('Log in is disabled until a password is typed', await page.evaluate(() => [...document.querySelectorAll('dialog[open] button')].find((b) => b.textContent.includes('log in and check')).disabled))
  await page.type('dialog[open] input[name=password]', 'a wrong password')
  await click('Yes, log in and check')
  await waitForDialog(/login was refused/)
  check('a refused login is said plainly, and the password box is emptied', /check the user name and the password/i.test(await dialog()) && (await page.$eval('dialog[open] input[name=password]', (i) => i.value)) === '')

  await page.evaluate(() => [...document.querySelectorAll('dialog[open] input[type=radio]')][1].click())
  await page.waitForFunction((key) => document.querySelector('dialog[open] [aria-label="The parent\'s public key"]')?.textContent === key, { timeout: 10000 }, publicKey)
  check('choosing the parent\'s key shows its public key to put on that computer', true)
  await click('Yes, log in and check')
  await waitForDialog(/Looks good/)
  const result = await dialog()
  check('step 3 says what the computer is', /macOS/.test(result) && /Apple/.test(result) && new RegExp(userInfo().username).test(result))
  const rows = await page.$$eval('dialog[open] .checks li', (items) => items.map((item) => item.innerText.replace(/\s+/g, ' ').trim()))
  check('step 3 lists every check, with the program for this system found', rows.length === 11 && rows.some((row) => /^✓ MetaService program/.test(row)) && rows.some((row) => /^✓ Apple's container tool/.test(row)) && rows.some((row) => /^✓ The parent can be reached/.test(row)), rows.join(' | '))
  check('step 3 says where MetaService would go, in plain words', /In a folder of that user/.test(result))
  check('Add machine is on, because everything that must pass passed', await page.evaluate(() => ![...document.querySelectorAll('dialog[open] button')].find((b) => b.textContent.trim() === 'Add machine').disabled))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'connect-result.png') })

  await click('Check another')
  await page.waitForSelector('dialog[open] #connect-host')
  check('Check another goes back to step 1', /Look at it/.test(await dialog()))
  await reachResult()

  // What will change, with the advanced choices pointing at throw-away folders, so nothing outside them is touched.
  const boxParent = mkdtempSync(join(tmpdir(), 'ms-e2e-box-'))
  const box = join(boxParent, 'metaservice-box')
  const keysBefore = readFileSync(sshd.authorized, 'utf8')
  await click('Add machine')
  await waitForDialog(/What will change on/)
  await page.waitForSelector('dialog[open] ol.plan')
  const plan = await page.$$eval('dialog[open] ol.plan > li', (items) => items.map((item) => item.querySelector('strong').textContent))
  check('What will change lists every step in plain words', plan.join(' | ') === 'Make the box folder | Copy the MetaService program | Enroll it with the parent | Start the program | Allow the parent\'s tunnel | Write the record', plan.join(' | '))
  check('it says the key line is the only change to a file that exists', /ONE line/.test(await dialog()) && /only change to a file that already exists/.test(await dialog()))
  check('Install is off until the machine has a valid name', await page.evaluate(() => !document.querySelector('dialog[open] button[type=submit]').disabled))
  await type('#remote-name', 'Bad Name')
  check('a bad machine name turns Install off and says why', /lowercase letters/i.test(await dialog()) && await page.evaluate(() => document.querySelector('dialog[open] button[type=submit]').disabled))
  await type('#remote-name', 'e2e-remote')
  check('the screen choice is off until it is ticked', await page.evaluate(() => ![...document.querySelectorAll('dialog[open] label.check')].find((l) => /see and control/.test(l.textContent)).querySelector('input').checked))
  await page.evaluate(() => [...document.querySelectorAll('dialog[open] label.check')].find((l) => /see and control/.test(l.textContent)).querySelector('input').click())
  await page.waitForFunction(() => /take its mouse and keyboard/.test(document.querySelector('dialog[open] ol.plan')?.innerText ?? ''), { timeout: 10000 })
  check('ticking it adds a plain sentence to What will change', true)
  await page.evaluate(() => { document.querySelector('dialog[open] details.advanced').open = true })
  await type('#remote-box', box)
  await type('#remote-ssh', dirname(sshd.authorized))
  await type('#remote-port', String(await freePort()))
  await page.waitForFunction((where) => document.querySelector('dialog[open] ol.plan')?.innerText.includes(where), { timeout: 10000 }, box)
  check('the plan follows the folder that was typed', true)
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'connect-plan.png') })
  await click('Install')
  await waitForDialog(/Installing e2e-remote/)
  await page.waitForFunction(() => /is added: it shows in Machines/.test(document.querySelector('dialog[open]')?.innerText ?? ''), { timeout: 120000 })
  const steps = await page.$$eval('dialog[open] ol[aria-label="Install steps"] li', (items) => items.map((item) => item.innerText.replace(/\s+/g, ' ').trim().split(' ')[0]))
  check('the install shows every step and ends with all of them done', steps.length === 9 && steps.every((mark) => mark === '✓'), steps.join(' '))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'connect-installed.png') })
  check('the box exists and the one key line was added', existsSync(join(box, 'manifest.json')) && existsSync(join(box, 'bin', 'metaservice-agent')) && readFileSync(sshd.authorized, 'utf8').split('\n').filter((line) => line.endsWith('metaservice-e2e-remote')).length === 1)
  check('the one-time token and the install marker are gone', !existsSync(join(box, 'state', 'enroll.token')) && !existsSync(join(box, '.partial')))
  await click('Done')
  await page.waitForFunction(() => /e2e-remote[\s\S]{0,500}(online|busy)/i.test(document.body.innerText), { timeout: 60000 })
  check('the new machine shows in Machines and is online', true)

  await page.goto(`${root.base}/#/machines/details?id=e2e-remote`)
  await page.waitForFunction(() => /connection\s*SSH tunnel · connected/i.test(document.body.innerText), { timeout: 30000 })
  check('the machine page says its SSH tunnel is connected, and where it is installed', /installed on\s*[^\n]*metaservice-box/i.test(await text()))
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'connect-machine-page.png') })

  // The screen: view only first, control only after the second, confirmed step, and the picture follows the pointer.
  await click('Open screen')
  await waitForDialog(/Screen of e2e-remote/)
  await page.waitForFunction(() => document.querySelector('dialog[open] canvas')?.width === 160, { timeout: 20000 })
  check('the screen opens as view only and a picture is drawn', /View only/.test(await dialog()))
  const pixel = () => page.evaluate(() => { const c = document.querySelector('dialog[open] canvas'); return [...c.getContext('2d').getImageData(Math.floor(c.width / 2), Math.floor(c.height / 2), 1, 1).data] })
  check('before control the centre is the plain background, not the pointer', (await pixel())[0] < 200)
  await click('Take control')
  check('control needs a confirm that names the computer', /Everything you type goes to that computer/.test(await dialog()) && /e2e-remote/.test(await dialog()))
  await click('Yes, take control')
  await page.waitForFunction(() => /You are controlling e2e-remote/.test(document.querySelector('dialog[open]')?.innerText ?? ''), { timeout: 10000 })
  check('the banner says the computer is being controlled', true)
  const box2 = await (await page.$('dialog[open] canvas')).boundingBox()
  await page.mouse.move(box2.x + box2.width / 2, box2.y + box2.height / 2)
  await page.waitForFunction(() => { const c = document.querySelector('dialog[open] canvas'); return c.getContext('2d').getImageData(Math.floor(c.width / 2), Math.floor(c.height / 2), 1, 1).data[0] > 200 }, { timeout: 10000 })
  check('moving the pointer over the picture moves the pointer on the computer', true)
  if (SHOTS) await page.screenshot({ path: join(SHOTS, 'connect-screen.png') })
  await click('End')
  await page.waitForFunction(() => !document.querySelector('dialog[open]'), { timeout: 10000 })
  check('End closes the screen', true)
  await page.goto(`${root.base}/#/machines`)
  await page.click('button[aria-label="Remove e2e-remote"]')
  await page.waitForFunction(() => /was installed on/.test(document.querySelector('dialog[open]')?.innerText ?? ''), { timeout: 10000 })
  check('Remove offers to take MetaService off that computer, or only to forget it', /Log in and take it away/.test(await dialog()) && /Only forget it here/.test(await dialog()))
  check('Remove is off until a way to log in is chosen', await page.evaluate(() => [...document.querySelectorAll('dialog[open] button')].find((b) => b.textContent.trim() === 'Remove machine').disabled))
  await page.evaluate(() => [...document.querySelectorAll('dialog[open] input[type=checkbox]')][0].click())
  await click('Remove machine')
  await page.waitForFunction(() => !document.body.innerText.includes('e2e-remote'), { timeout: 60000 })
  check('the machine is gone from the dashboard', true)
  check('the box is gone and authorized_keys is exactly as it was', !existsSync(box) && readFileSync(sshd.authorized, 'utf8') === keysBefore)
  await page.waitForFunction(() => !document.querySelector('dialog[open]'), { timeout: 10000 })
  check('no script errors and no policy violations', errors.length === 0 && (await page.evaluate(() => window.__csp)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  root.child.kill()
  sshd.child.kill()
}
const failed = results.filter((ok) => !ok).length
console.log(`\n${results.length - failed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
