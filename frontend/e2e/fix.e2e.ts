// End-to-end test of "Install it for me" on the Check step, in a real browser against a real Root. The other computer is a pretend Debian behind a real OpenSSH server on loopback
// (contract/root_tests/fakes/fake_linux.py): its sudo, apt-get and incus are stubs, so no real package or password is involved. The password is a recognizable fake.
// Needs: the Root build (`swift build`), Google Chrome (or CHROME_PATH), /usr/sbin/sshd, python3, `bun install` and `bun run build` in frontend/. Run: bun e2e/fix.e2e.ts
import { spawn } from 'node:child_process'
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'
import { userInfo } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline'
import puppeteer from 'puppeteer-core'
import { ADMIN, createAdmin } from './support/admin.ts'
import { check, finish } from './support/check.ts'
import { readRecord, textField } from './support/json.ts'
import { wait } from './support/net.ts'
import { chromePath, repo } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'
import { SCAN_PREFIX, scanSettings, startRoot } from './support/root.ts'
import { findRow, labelsAligned, readRows } from './support/checkRows.ts'

const SETUP_TOKEN = 'e2e-setup-token-0123456789abcdef'
const SHORT_WAIT_MS = 10000
const STEP_WAIT_MS = 20000
const INSTALL_WAIT_MS = 60000
/** The install route answers 3 times a minute; the three tries before this step used them up. */
const FIX_WINDOW_MS = 61000
const WRONG_PASSWORD = 'Wrong-Pw-e2e-31c7'
const ROW = 'dialog[open] .checks li'
const OFFER = `${ROW} button.offer`
const VERDICT = /things? to fix before|All \d+ checks passed|Ready to add|cannot be added/

interface Fake { port: number; dir: string; authorized: string; fingerprint: string; password: string }

const python = spawn('python3', ['-m', 'contract.root_tests.fakes.serve_fake_linux'], { cwd: repo, env: { ...process.env, PYTHONPATH: repo }, stdio: ['pipe', 'pipe', 'inherit'] })
const firstLine = await new Promise<string>((done, fail) => {
  python.once('error', fail)
  createInterface({ input: python.stdout }).once('line', done)
})
const fake = JSON.parse(firstLine) as Fake
const root = await startRoot({
  envLines: [`ROOT_SETUP_TOKEN=${SETUP_TOKEN}`, ...scanSettings().envLines],
  args: ['--remote-allow-loopback', 'yes', '--remote-engine', 'simulated', '--remote-tries', '30'],
  processEnv: scanSettings().processEnv,
})
const cookie = await createAdmin(root.base, SETUP_TOKEN)
const publicKey = textField(await readRecord(await fetch(`${root.base}/api/remote/key`, { headers: { Cookie: cookie } }), 'the parent key'), 'public_key', 'the parent key')
appendFileSync(fake.authorized, publicKey + '\n')

const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const errors: string[] = []
const requestBodies: string[] = []

async function waitForDialog(b: Browse, pattern: RegExp, timeout = STEP_WAIT_MS): Promise<void> {
  try {
    await b.until((source) => new RegExp(source, 'i').test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout }, pattern.source)
  } catch {
    throw new Error(`waiting for ${pattern} failed; the rows are: ${(await rows(b)).join(" | ")}`)
  }
}

const rows = async (b: Browse): Promise<string[]> => (await readRows(b.page)).map((row) => `${row.state}: ${row.shown}`)

/** Waits until the row of this id has this state (ready is a tick). */
async function waitForState(b: Browse, id: string, state: string): Promise<void> {
  await b.until((selector, wanted) => document.querySelector(selector)?.getAttribute('data-state') === wanted, { timeout: INSTALL_WAIT_MS }, `${ROW}[data-check=${id}]`, state)
}

/** Sign in, Find machines, Add on a row, then the address of the pretend computer, its host key, and the key login: the path to the Check step. */
async function reachTheCheck(b: Browse, first: boolean): Promise<void> {
  if (first) {
    await b.page.goto(root.base, { waitUntil: 'networkidle0' })
    await b.page.type('input[name=username]', ADMIN.username)
    await b.page.type('input[name=password]', ADMIN.password)
    await b.click('Sign in')
    await b.until(() => document.body.innerText.includes('No machines yet'), { timeout: SHORT_WAIT_MS })
    await b.openMachinesMenu()
    await b.page.click('aside.side a[href="#/machines/find"]')
    await b.until(() => document.body.innerText.includes('Looks at'), { timeout: SHORT_WAIT_MS })
    await b.click('Scan now')
    const addButton = `button[aria-label="Add ${SCAN_PREFIX}.40"]`
    await b.page.waitForSelector(addButton, { timeout: STEP_WAIT_MS })
    await b.page.click(addButton)
    await b.page.waitForSelector('dialog[open] #connect-host')
  }
  await b.type('#connect-host', '127.0.0.1')
  await b.type('#connect-port', String(fake.port))
  await b.click('Look at it')
  await waitForDialog(b, /Found a computer at/)
  await b.type('#connect-user', userInfo().username)
  await b.click('Log in and check')
  await waitForDialog(b, VERDICT)
}

async function offers(b: Browse): Promise<void> {
  const list = await readRows(b.page)
  const incus = findRow(list, 'vm_tool')
  const python = findRow(list, 'python')
  check('a missing Incus is a cross with one plain sentence, its manual steps with the command, AND an Install it for me button',
    incus?.state === 'blocking' && /Incus is the tool that makes the VMs/.test(incus.shown) && incus.all.includes('Run sudo apt install incus') && incus.manualSteps && incus.buttons.includes('Install it for me'), incus?.all)
  check('Python is a cross with the button too, and the ticks have none', python?.state === 'blocking' && python.buttons.includes('Install it for me') && list.filter((row) => row.state === 'ready').every((row) => row.buttons.length === 0))
  check('the command to run by hand is in a code box with a Copy button', (await b.page.$(`${ROW}[data-check=vm_tool] .codebox code`)) !== null && (await b.page.$(`${ROW}[data-check=vm_tool] .codebox button[aria-label="Copy this command"]`)) !== null)
  check('the button is a button and there is no password field before it is pressed', (await b.page.$$('dialog[open] input[type=password]')).length === 0)
  check('every label starts at the same x on this list too', await labelsAligned(b.page))
  await b.shot('fix-offer.png')
}

async function wrongPassword(b: Browse): Promise<void> {
  const button = (await b.page.$$(OFFER))[0]
  if (!button) throw new Error('no Install it for me button')
  await button.click()
  await b.page.waitForSelector('dialog[open] input[name=sudo-password]')
  const field = await b.page.$eval('dialog[open] input[name=sudo-password]', (node) => ({ type: node.getAttribute('type'), autocomplete: node.getAttribute('autocomplete') }))
  check('the password field hides what is typed and is not offered to a password manager', field.type === 'password' && field.autocomplete === 'off', JSON.stringify(field))
  check('the field has an eye to show what was typed', (await b.page.$('dialog[open] .fix button.eye')) !== null)
  check('the field says whose password it is, in plain words', /Password of .* on that computer/i.test(await b.dialogText()) && /never saved/.test(await b.dialogText()))
  check('Install is off until something is typed', await b.isDisabled('Install'))
  await b.page.type('dialog[open] input[name=sudo-password]', WRONG_PASSWORD)
  await b.shot('fix-password.png')
  await b.click('Install')
  await waitForDialog(b, /did not accept that password/)
  check('a wrong password is said plainly and nothing is ticked', /did not accept that password/.test(await b.dialogText()) && findRow(await readRows(b.page), 'vm_tool')?.state === 'blocking')
  check('the field is empty again after the answer', (await b.page.$eval('dialog[open] input[name=sudo-password]', (node) => (node instanceof HTMLInputElement ? node.value : 'x'))) === '')
  await b.shot('fix-wrong.png')
}

async function rightPassword(b: Browse): Promise<void> {
  await b.page.type('dialog[open] input[name=sudo-password]', fake.password)
  await b.click('Install')
  await waitForState(b, 'vm_tool', 'ready')
  const list = await readRows(b.page)
  check('after the install the Incus cross became a tick', findRow(list, 'vm_tool')?.state === 'ready' && findRow(list, 'vm_tool')?.manualSteps === false, (await rows(b)).join(' | '))
  check('Python is still a cross with its button', findRow(list, 'python')?.state === 'blocking' && findRow(list, 'python')?.buttons.includes('Install it for me') === true)
  await b.shot('fix-after.png')
  const log = readFileSync(join(fake.dir, 'commands.log'), 'utf8')
  check('the other computer ran apt, set Incus up and added the user to the incus-admin group', /install incus/.test(log) && /admin init --minimal/.test(log) && /usermod -a -G incus-admin build/.test(log), log.slice(-300))
  const python = (await b.page.$$(OFFER))[0]
  if (!python) throw new Error('no Install it for me button for Python')
  await python.click()
  await b.page.waitForSelector('dialog[open] input[name=sudo-password]')
  await b.page.type('dialog[open] input[name=sudo-password]', fake.password)
  await b.click('Install')
  await waitForState(b, 'python', 'ready')
  check('Python became a tick too', findRow(await readRows(b.page), 'python')?.state === 'ready')
}

async function nothingKept(b: Browse): Promise<void> {
  const html = await b.run(() => document.documentElement.outerHTML + JSON.stringify(Object.entries(localStorage)) + JSON.stringify(Object.entries(sessionStorage)))
  check('the password is nowhere in the page, its storage or the address', !html.includes(fake.password) && !html.includes(WRONG_PASSWORD) && !b.page.url().includes(fake.password))
  const audit = await (await fetch(`${root.base}/api/audit`, { headers: { Cookie: cookie } })).text()
  check('the password is not in the audit log, and the install is', !audit.includes(fake.password) && !audit.includes(WRONG_PASSWORD) && audit.includes('remote.fix'))
  const sent = requestBodies.filter((body) => body.includes('sudo_password'))
  check('the password travelled in request bodies only, one per try (two Incus tries, one Python)', sent.length === 3, String(sent.length))
}

/** A computer with an NVIDIA card: the toolkit row is a cross with its fix line and a button that says it adds NVIDIA's package source; one click installs it and the row turns to a tick. */
async function toolkit(b: Browse): Promise<void> {
  writeFileSync(join(fake.dir, 'state', 'nvidia'), '')
  await b.click('Check another')
  await b.page.waitForSelector('dialog[open] #connect-host')
  await reachTheCheck(b, false)
  const list = await readRows(b.page)
  const row = findRow(list, 'gpu_toolkit')
  check('a computer with an NVIDIA card gets a toolkit row: a dashed cross, the card, the manual steps and a button that says it adds NVIDIA\'s package source',
    row?.state === 'optional' && /NVIDIA GeForce RTX 5090/.test(row.shown) && row.all.includes("Follow NVIDIA's install guide") && row.buttons.includes("Install it for me (adds NVIDIA's package source)"), row?.all)
  check('the Incus and Python rows are unchanged ticks and there is exactly one toolkit row', list.filter((entry) => entry.id === 'gpu_toolkit').length === 1 && findRow(list, 'vm_tool')?.state === 'ready' && findRow(list, 'python')?.state === 'ready')
  check('the toolkit does not block adding: Add machine is on, no card has the red outline and the verdict says so', !(await b.isDisabled('Add machine')) && (await b.page.$$('dialog[open] section.card.has-bad')).length === 0 && /does not block adding/.test(await b.dialogText()))
  await b.shot('fix-toolkit-offer.png')
  const target = (await b.page.$$(OFFER))[0]
  if (!target) throw new Error('no button under the toolkit row')
  await target.click()
  await b.page.waitForSelector('dialog[open] input[name=sudo-password]')
  const said = await b.dialogText()
  check('before the press it says in plain words that it adds NVIDIA\'s package source and installs the toolkit, and the password is used once', /Adds NVIDIA's own package source and signing key/.test(said) && /installs NVIDIA's container toolkit/.test(said) && /never saved/.test(said), said.slice(-400))
  await b.page.type('dialog[open] input[name=sudo-password]', fake.password)
  await b.shot('fix-toolkit-password.png')
  await wait(FIX_WINDOW_MS)
  await b.click('Install')
  try {
    await waitForState(b, 'gpu_toolkit', 'ready')
  } catch {
    throw new Error(`the toolkit row did not turn to a tick; the rows are: ${(await rows(b)).join(" | ")}`)
  }
  check('after the install the toolkit row is a tick', findRow(await readRows(b.page), 'gpu_toolkit')?.state === 'ready')
  await b.shot('fix-toolkit-after.png')
  const log = readFileSync(join(fake.dir, 'commands.log'), 'utf8')
  check('the other computer fetched NVIDIA\'s key and package list, signed the source and installed nvidia-container-toolkit', /libnvidia-container\/gpgkey/.test(log) && /gpg --dearmor/.test(log) && /nvidia-container-toolkit\.list/.test(log) && /install nvidia-container-toolkit/.test(log), log.slice(-500))
  const html = await b.run(() => document.documentElement.outerHTML + JSON.stringify(Object.entries(localStorage)))
  check('the password is still nowhere in the page or its storage', !html.includes(fake.password))
  await b.page.setViewport({ width: 400, height: 900 })
  await b.shot('fix-toolkit-after-phone.png', true)
  check('the check list has no sideways scrolling on a phone', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await b.page.setViewport({ width: 1280, height: 900 })
}

async function windows(b: Browse): Promise<void> {
  writeFileSync(join(fake.dir, 'state', 'windows'), '')
  await b.click('Check another')
  await b.page.waitForSelector('dialog[open] #connect-host')
  await reachTheCheck(b, false)
  const list = await readRows(b.page)
  check('a Windows computer is a Login tick and one plain System cross that says why, with no button and nothing else', list.length === 2 && list[0]?.state === 'ready' && list[1]?.state === 'blocking' && /Windows is not supported yet\. Please use a Linux or Mac computer/.test(list[1].shown) && list.every((row) => row.buttons.length === 0), (await rows(b)).join(' | '))
  check('Add machine stays off for Windows', await b.isDisabled('Add machine'))
  await b.shot('fix-windows.png')
}

try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1280, height: 900 })
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|422|502)/.test(message.text()) && errors.push(message.text()))
  page.on('request', (request) => request.method() === 'POST' && requestBodies.push(request.postData() ?? ''))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { window.violation = event.violatedDirective }))
  const b = browse(page)
  await reachTheCheck(b, true)
  await offers(b)
  await wrongPassword(b)
  await rightPassword(b)
  await nothingKept(b)
  await toolkit(b)
  await windows(b)
  check('no script errors and no policy violations', errors.length === 0 && (await page.evaluate(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  root.child.kill()
  python.stdin.end('\n')
  if (!existsSync(fake.dir)) console.log('the pretend computer is gone')
}
finish()
