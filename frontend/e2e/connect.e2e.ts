// End-to-end test of Add a machine (a computer found on the network, then looked at, installed over SSH, watched, and removed) in a real browser against a real Root
// and a real OpenSSH server on loopback. The way in is Find machines: scan, then Add on a row. There is no other button.
// Needs: the Root build and the macOS Agent build (`swift build`), Google Chrome (or CHROME_PATH), /usr/sbin/sshd, and `bun install` in frontend/. Run: bun e2e/connect.e2e.ts
import { appendFileSync, existsSync, mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir, userInfo } from 'node:os'
import { dirname, join } from 'node:path'
import puppeteer, { type HTTPRequest } from 'puppeteer-core'
import { ADMIN, createAdmin } from './support/admin.ts'
import { check, finish } from './support/check.ts'
import { readRecord, textField } from './support/json.ts'
import { freePort } from './support/net.ts'
import { owlAbsent, owlShown } from './support/owls.ts'
import { chromePath } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'
import { SCAN_PREFIX, scanSettings, startRoot } from './support/root.ts'
import { startSshd } from './support/sshd.ts'
import { findRow, labelsAligned, readRows } from './support/checkRows.ts'
import { expandAll } from './machine/environment.ts'
import { openMachine, openTab } from './machine/steps.ts'
import type { Requirement } from '../src/lib/types.ts'

const SETUP_TOKEN = 'e2e-setup-token-0123456789abcdef'
const KEY_LINE = 'dialog[open] [aria-label="Command that lets MetaService in"]'
const NO_SSH_PORT = '1'
const NAME = 'e2e-remote'
const FOUND_ADDRESS = `${SCAN_PREFIX}.40`
const SHORT_WAIT_MS = 10000
const STEP_WAIT_MS = 20000
const INSTALL_WAIT_MS = 120000
const ONLINE_WAIT_MS = 60000
const ALL_CHECKS = 11
const READY_VERDICT = /All \d+ checks passed/
const ALL_INSTALL_STEPS = 9

const sshd = await startSshd()
const root = await startRoot({
  envLines: [`ROOT_SETUP_TOKEN=${SETUP_TOKEN}`, ...scanSettings().envLines],
  args: ['--remote-allow-loopback', 'yes', '--remote-engine', 'simulated', '--remote-tries', '30'],
  processEnv: scanSettings().processEnv,
})
/** The admin is made through the API, so the page only has to sign in. The parent's key is read now and allowed on the test server later, in the middle of the test. */
const cookie = await createAdmin(root.base, SETUP_TOKEN)
const keyReply = await fetch(`${root.base}/api/remote/key`, { headers: { Cookie: cookie } })
const publicKey = textField(await readRecord(keyReply, 'the parent key'), 'public_key', 'the parent key')

const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const errors: string[] = []

/** Signs in on the login page, which is the first thing a person sees. */
async function signInOnThePage(b: Browse): Promise<void> {
  await b.page.goto(root.base, { waitUntil: 'networkidle0' })
  await b.page.type('input[name=username]', ADMIN.username)
  await b.page.type('input[name=password]', ADMIN.password)
  await b.click('Sign in')
  await b.until(() => document.body.innerText.includes('No machines yet'), { timeout: SHORT_WAIT_MS })
}

/** The one way in: Find machines, Scan now, then Add on a row. The dialog opens with that row's address filled in. */
async function startFromFindMachines(b: Browse): Promise<void> {
  await b.openMachinesMenu()
  await b.page.click('aside.side a[href="#/machines/find"]')
  await b.until(() => document.body.innerText.includes('Looks at'), { timeout: SHORT_WAIT_MS })
  await b.click('Scan now')
  const addButton = `button[aria-label="Add ${FOUND_ADDRESS}"]`
  await b.page.waitForSelector(addButton, { timeout: STEP_WAIT_MS })
  check('Find machines lists the computers it found, each with an Add button', (await b.page.$$('button[aria-label^="Add "]')).length >= 1)
  await b.shot('connect-find.png')
  await b.page.click(addButton)
  await b.page.waitForSelector('dialog[open] #connect-host')
  const filledIn = await b.run(() => document.querySelector<HTMLInputElement>('dialog[open] #connect-host')?.value ?? '')
  check('Add opens the Add a machine dialog on step 1 with the row\'s address filled in', /Add a machine/.test(await b.dialogText()) && filledIn === FOUND_ADDRESS, filledIn)
}

async function stepOneChecks(b: Browse): Promise<void> {
  check('the dialog says it only looks', /nothing is installed or changed/i.test(await b.dialogText()))
  await b.type('#connect-host', '')
  check('Look at it is disabled until an address is typed', await b.isDisabled('Look at it'))
  await b.type('#connect-host', '-oProxyCommand=evil')
  check('an address that could be an ssh option is refused on the spot', /address/i.test(await b.dialogText()) && await b.isDisabled('Look at it'))
  await b.type('#connect-host', '127.0.0.1')
  await b.type('#connect-port', NO_SSH_PORT)
  await b.click('Look at it')
  await waitForDialog(b, /did not show an SSH host key|cannot reach that computer/)
  check('a port with no SSH gives a plain message and stays on step 1', /did not show an SSH host key/i.test(await b.dialogText()) && (await b.page.$('#connect-host')) !== null)
}

async function waitForDialog(b: Browse, pattern: RegExp, timeout = STEP_WAIT_MS): Promise<void> {
  try {
    await b.until((source) => new RegExp(source, 'i').test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout }, pattern.source)
  } catch {
    throw new Error(`waiting for ${pattern} failed; the dialog says: ${(await b.dialogText()).replace(/\s+/g, ' ').slice(-500)}`)
  }
}

async function stepTwo(b: Browse): Promise<void> {
  await b.type('#connect-port', String(sshd.port))
  await b.click('Look at it')
  await waitForDialog(b, /Found a computer at/)
  const shown = (await b.page.$eval('dialog[open] [aria-label="ID code of the computer (host key fingerprint)"]', (node) => node.textContent ?? '')).replace(/\s+/g, '')
  check("step 2 shows the server's real host key fingerprint", shown === sshd.fingerprint, `${shown} vs ${sshd.fingerprint}`)
  await b.shot('connect-confirm.png')
  await b.type('#connect-user', 'dalang mac')
  check('a user name with a space shows a warning at once', /cannot have spaces/.test(await b.dialogText()))
  await b.shot('connect-user-space.png')
  await b.type('#connect-user', userInfo().username)
  check('a good user name shows no warning', !/cannot have spaces/.test(await b.dialogText()))
  const dialog = await b.dialogText()
  check('a computer that takes only keys gets the key steps at once and no password box', /only accepts keys/.test(dialog) && (await b.page.$('dialog[open] input[name=password]')) === null)
  const shownLine = await b.page.$eval(KEY_LINE, (node) => node.textContent ?? '')
  check('the key steps show a line with the public key to paste on that computer', shownLine.includes(publicKey))
  await b.click('Log in and check')
  await waitForDialog(b, /refused/)
  check('before the key is allowed the login is refused and said plainly', /refused/i.test(await b.dialogText()) && !READY_VERDICT.test(await b.dialogText()))
  appendFileSync(sshd.authorized, publicKey + '\n')
}

async function stepThree(b: Browse): Promise<void> {
  await b.click('Log in and check')
  await waitForDialog(b, READY_VERDICT)
  const result = await b.dialogText()
  check('step 3 says what the computer is', /macOS/.test(result) && /Apple/.test(result) && new RegExp(userInfo().username).test(result))
  const rows = await readRows(b.page)
  const shown = rows.map((row) => `${row.state}: ${row.shown}`)
  const ready = (id: string) => findRow(rows, id)?.state === 'ready'
  check('step 3 lists every check, with the program for this system found',
    rows.length === ALL_CHECKS && ready('agent') && ready('parent') && ready('vm_tool') && /Apple's container tool/.test(findRow(rows, 'vm_tool')?.shown ?? ''), shown.join(' | '))
  check('step 3 says where MetaService would go, in plain words', /In a folder of that user/.test(result))
  check('Add machine is on, because everything that must pass passed', !(await b.isDisabled('Add machine')))
  check('no row says "maybe": every row is a tick or a cross, drawn as a mark with its own shape', rows.every((row) => ['ready', 'blocking', 'optional'].includes(row.state) && row.marks === 1))
  check('a tick is one short line: no row has manual steps or a button, and every one has a value', rows.every((row) => !row.manualSteps && row.buttons.length === 0))
  check('the rows are in three cards by topic', (await b.page.$$eval('dialog[open] section.cx-card h4', (titles) => titles.map((title) => title.textContent))).join('|') === 'This computer|Software it needs|Connection')
  check('every label starts at the same x, so the rows are aligned', await labelsAligned(b.page))
  check('the ring says in words how many checks are ready', (await b.page.$$eval('dialog[open] [role=img]', (rings) => rings.map((ring) => ring.getAttribute('aria-label')))).includes(`${ALL_CHECKS} of ${ALL_CHECKS} checks ready`))
  check('the host key is short and has a Copy button', /Host key\s+SHA256:\S+…\S+/.test(result) && (await b.page.$('dialog[open] button[aria-label="Copy the host key"]')) !== null)
  await b.shot('connect-result.png')
  await onPhone(b, 'connect-result-phone.png', 'the Check step')
  await b.click('Check another')
  await b.page.waitForSelector('dialog[open] #connect-host')
  check('Check another goes back to step 1', /Look at it/.test(await b.dialogText()))
  await failingResult(b)
  await reachResult(b)
}

const MISSING_PYTHON = { id: 'python', label: 'Python (runs the chat)', ok: false, detail: 'Not installed.', fix: 'Install it with sudo apt install python3, then check again.' }
const MISSING_INCUS = { id: 'vm_tool', label: 'Incus (makes the VMs)', ok: false, detail: 'Not installed.', fix: 'Install Incus on that computer: sudo apt install incus' }

/** A computer that misses two things (Incus and Python): both are crosses with a plain sentence and their manual steps, and Add machine stays off. The answer is made up here, because the test server is always a ready Mac. */
async function failingResult(b: Browse): Promise<void> {
  await b.page.setRequestInterception(true)
  const answer = async (request: HTTPRequest): Promise<void> => {
    if (!request.url().endsWith('/api/remote/verify')) return void (await request.continue())
    const passing = (id: string, label: string): Requirement => ({ id, label, ok: true, detail: 'Found.' })
    const requirements = [passing('login', 'Login'), passing('system', 'System'), passing('vm_support', 'Can run workloads'), MISSING_INCUS, MISSING_PYTHON]
    const facts = { os: 'Linux', arch: 'x86_64', version: 'Ubuntu 24.04', chip: 'AMD Ryzen 9 5950X', user: 'luca', home: '/home/luca', cpu_cores: 32, ram_mb: 64000, disk_free_gb: 79 }
    const body = { host: '127.0.0.1', fingerprint: sshd.fingerprint, facts, requirements, can_add: false, isolation: ['folder'], system: 'Ubuntu 24.04 · AMD Ryzen 9 5950X · x86_64' }
    await request.respond({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
  }
  b.page.on('request', answer)
  await b.type('#connect-host', '127.0.0.1')
  await b.type('#connect-port', String(sshd.port))
  await b.click('Look at it')
  await waitForDialog(b, /Found a computer at/)
  await b.type('#connect-user', userInfo().username)
  await b.click('Log in and check')
  await waitForDialog(b, /things? to fix before this computer can be added/)
  const rows = await readRows(b.page)
  const python = findRow(rows, 'python')
  const incus = findRow(rows, 'vm_tool')
  check('a missing requirement is a cross, says one plain sentence, and keeps what to do behind "Show the manual steps"',
    python?.state === 'blocking' && /Python runs the chat\. It is not installed on this computer\./.test(python.shown) && python.all.includes('Install it with sudo apt install python3') && !python.shown.includes('sudo apt')
      && incus?.state === 'blocking' && /Incus is the tool that makes the VMs/.test(incus.shown) && incus.all.includes('Install Incus on that computer: sudo apt install incus') && python.manualSteps && incus.manualSteps, rows.map((row) => row.shown).join(' | '))
  check('only crosses have manual steps, and nothing is a "maybe"', rows.filter((row) => row.manualSteps).length === 2 && rows.every((row) => row.state === 'ready' || row.state === 'blocking'))
  check('the card that has a cross gets the red outline and the others do not', (await b.page.$$eval('dialog[open] section.cx-card', (cards) => cards.map((card) => card.classList.contains('has-bad')))).join() === 'false,true')
  check('a cross says in words what is wrong and the count of ready checks says so too', /2 things to fix before this computer can be added/.test(await b.dialogText()) && (await b.page.$('dialog[open] [role=img][aria-label="3 of 5 checks ready"]')) !== null)
  check('Add machine stays off until every cross is fixed', await b.isDisabled('Add machine'))
  await b.shot('connect-result-crosses.png')
  b.page.off('request', answer)
  await b.page.setRequestInterception(false)
  await b.click('Check another')
  await b.page.waitForSelector('dialog[open] #connect-host')
}

/** The path to step 3 again, from step 1. */
async function reachResult(b: Browse): Promise<void> {
  await b.type('#connect-host', '127.0.0.1')
  await b.type('#connect-port', String(sshd.port))
  await b.click('Look at it')
  await waitForDialog(b, /Found a computer at/)
  await b.type('#connect-user', userInfo().username)
  await b.click('Log in and check')
  await waitForDialog(b, READY_VERDICT)
}

/** What will change, with the advanced choices pointing at throw-away folders, so nothing outside them is touched. Returns the box folder and the keys as they were. */
async function installIntoThrowAwayFolder(b: Browse): Promise<{ box: string; keysBefore: string }> {
  const box = join(mkdtempSync(join(tmpdir(), 'ms-e2e-box-')), 'metaservice-box')
  const keysBefore = readFileSync(sshd.authorized, 'utf8')
  await b.click('Add machine')
  await waitForDialog(b, /will change on/)
  await b.page.waitForSelector('dialog[open] ol.plan')
  const plan = await b.page.$$eval('dialog[open] ol.plan > li', (items) => items.map((item) => item.querySelector('strong')?.textContent ?? ''))
  check('What will change lists every step in plain words', plan.join(' | ') === "Make the box folder | Copy the MetaService program | Enroll it with the parent | Start the program | Allow the parent's tunnel | Write the record", plan.join(' | '))
  check('it says the key line is the only change to a file that exists', /ONE line/.test(await b.dialogText()) && /only change to a file that already exists/.test(await b.dialogText()))
  check('Install is off until the machine has a valid name', await b.run(() => !document.querySelector<HTMLButtonElement>('dialog[open] button[type=submit]')?.disabled))
  await b.type('#remote-name', 'Bad Name')
  check('a bad machine name turns Install off and says why', /lowercase letters/i.test(await b.dialogText()) && await b.run(() => document.querySelector<HTMLButtonElement>('dialog[open] button[type=submit]')?.disabled ?? false))
  await b.type('#remote-name', NAME)
  await b.run(() => { const details = document.querySelector<HTMLDetailsElement>('dialog[open] details.advanced'); if (details) details.open = true })
  await b.type('#remote-box', box)
  await b.type('#remote-ssh', dirname(sshd.authorized))
  await b.type('#remote-port', String(await freePort()))
  await b.until((where) => document.querySelector<HTMLElement>('dialog[open] ol.plan')?.innerText.includes(where), { timeout: SHORT_WAIT_MS }, box)
  check('the plan follows the folder that was typed', true)
  await b.shot('connect-plan.png')
  await onPhone(b, 'connect-plan-phone.png', 'What will change')
  return { box, keysBefore }
}

const PHONE = { width: 400, height: 900 }
const DESKTOP = { width: 1280, height: 800 }

/** Looks at the open dialog on a phone: a picture, and no sideways scrolling. Then back to a desktop window. */
async function onPhone(b: Browse, picture: `${string}.png`, what: string): Promise<void> {
  await b.page.setViewport(PHONE)
  await b.shot(picture)
  check(`${what} has no sideways scrolling on a phone`, await b.run(() => document.documentElement.scrollWidth <= window.innerWidth && (document.querySelector('dialog[open]')?.scrollWidth ?? 0) <= (document.querySelector('dialog[open]')?.clientWidth ?? 0)))
  await b.page.setViewport(DESKTOP)
}

const FAIL_REASON = 'The VM maker could not be installed. The computer could not reach the internet to download it.'
const FAKE_JOB_ID = 'e2e-failed-job'

/** An install that stops at step 5 (the answer is made up here): the failed view says why, marks the step, and Try again goes back to the plan with the choices kept. */
async function failedInstall(b: Browse): Promise<void> {
  const labels = ['Check the computer', 'Make the box folder', 'Copy the program', 'Set up Python', 'Set up the VM maker', 'Add the key line', 'Start the program', 'Connect to the parent', 'Check it is online']
  const steps = labels.map((label, index) => ({ id: `s${index}`, label, state: index < 4 ? 'done' : index === 4 ? 'failed' : 'pending' }))
  const job = { id: FAKE_JOB_ID, name: NAME, state: 'failed', steps, error: FAIL_REASON }
  await b.page.setRequestInterception(true)
  const answer = async (request: HTTPRequest): Promise<void> => {
    const url = request.url()
    if (url.endsWith('/api/remote/installs')) return void (await request.respond({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: FAKE_JOB_ID }) }))
    if (url.endsWith(`/api/remote/installs/${FAKE_JOB_ID}`)) return void (await request.respond({ status: 200, contentType: 'application/json', body: JSON.stringify(job) }))
    await request.continue()
  }
  b.page.on('request', answer)
  await b.click('Install')
  await waitForDialog(b, /Stopped at step 5/)
  const text = await b.dialogText()
  const states = await b.page.$$eval('dialog[open] ol[aria-label="Install steps"] li', (items) => items.map((item) => item.getAttribute('data-state')))
  check('a failed install says where it stopped, the plain reason, and marks that step', states.join() === 'done,done,done,done,failed,pending,pending,pending,pending' && text.includes(FAIL_REASON) && /stopped after \d+:\d\d/.test(text))
  check('the failed view has the ring in words and Try again beside Close', (await b.page.$('dialog[open] [role=img][aria-label="4 of 9 install steps done"]')) !== null && !(await b.isDisabled('Try again')) && !(await b.isDisabled('Close')))
  await owlAbsent(b, 'busy', 'the failed install view')
  await owlAbsent(b, 'done', 'the failed install view')
  await b.shot('connect-failed.png')
  await onPhone(b, 'connect-failed-phone.png', 'the failed view')
  await b.click('Try again')
  await b.page.waitForSelector('dialog[open] #remote-name')
  check('Try again goes back to the plan with the name kept and Install ready', (await b.run(() => document.querySelector<HTMLInputElement>('dialog[open] #remote-name')?.value ?? '')) === NAME && !(await b.isDisabled('Install')))
  b.page.off('request', answer)
  await b.page.setRequestInterception(false)
}

async function installAndFollow(b: Browse, box: string): Promise<void> {
  await b.click('Install')
  await waitForDialog(b, new RegExp(`Installing ${NAME}`))
  check('while it installs there is a ring, a timer and a Close button that is off', /time so far \d+:\d\d/.test(await b.dialogText()) && await b.isDisabled('Close'))
  await owlShown(b, 'busy', 'the install progress view')
  await onPhone(b, 'connect-installing-phone.png', 'the install progress view')
  await b.until((name) => (document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? '').includes(`${name} is online`), { timeout: INSTALL_WAIT_MS }, NAME)
  const steps = await b.page.$$eval('dialog[open] ol[aria-label="Install steps"] li', (items) => items.map((item) => item.getAttribute('data-state')))
  check('the install shows every step and ends with all of them done', steps.length === ALL_INSTALL_STEPS && steps.every((state) => state === 'done'), steps.join(' '))
  check('the done view says how long it took and links to the machine\'s page', /All \d+ steps done in \d+:\d\d/.test(await b.dialogText()) && (await b.page.$(`dialog[open] a[href*="${NAME}"]`)) !== null)
  await owlShown(b, 'done', 'the install done view')
  await b.shot('connect-installed.png')
  await onPhone(b, 'connect-installed-phone.png', 'the install done view')
  const keyLines = readFileSync(sshd.authorized, 'utf8').split('\n').filter((line) => line.endsWith(`metaservice-${NAME}`))
  check('the box exists and the one key line was added', existsSync(join(box, 'manifest.json')) && existsSync(join(box, 'bin', 'metaservice-agent')) && keyLines.length === 1)
  check('the one-time token and the install marker are gone', !existsSync(join(box, 'state', 'enroll.token')) && !existsSync(join(box, '.partial')))
  await b.click('Done')
  await b.openMachinesMenu()
  await b.page.click('aside.side a[href="#/machines"]')
  await b.until((name) => new RegExp(`${name}[\\s\\S]{0,500}(online|busy)`, 'i').test(document.body.innerText), { timeout: ONLINE_WAIT_MS }, NAME)
  check('the new machine shows in Machines and is online', true)
}

async function machinePage(b: Browse): Promise<void> {
  await openMachine(b, root.base, NAME)
  await openTab(b, 'Environment')
  await expandAll(b)
  await b.until(() => /tunnel\s*SSH tunnel · connected/i.test(document.body.innerText), { timeout: 30000 })
  check('the Environment tab says its SSH tunnel is connected, and where the helper is installed', /helper folder\s*[^\n]*metaservice-box/i.test(await b.text()))
  await b.shot('connect-machine-page.png')
}

async function removeIt(b: Browse, box: string, keysBefore: string): Promise<void> {
  await b.page.goto(`${root.base}/#/machines`)
  await b.page.click(`button[aria-label="Remove ${NAME}"]`)
  await b.until(() => /was installed on/.test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout: SHORT_WAIT_MS })
  const offer = await b.dialogText()
  check('Remove offers to take MetaService off that computer, or only to forget it', /Log in and take it away/.test(offer) && /Only forget it here/.test(offer))
  check('Remove is off until a way to log in is chosen', await b.isDisabled('Remove machine'))
  await b.run(() => document.querySelector<HTMLInputElement>('dialog[open] input[type=checkbox]')?.click())
  await b.click('Remove machine')
  await b.until((name) => !document.body.innerText.includes(name), { timeout: 60000 }, NAME)
  check('the machine is gone from the dashboard', true)
  check('the box is gone and authorized_keys is exactly as it was', !existsSync(box) && readFileSync(sshd.authorized, 'utf8') === keysBefore)
  await b.until(() => !document.querySelector('dialog[open]'), { timeout: SHORT_WAIT_MS })
}

try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1280, height: 800 })
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|422|502)/.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { window.violation = event.violatedDirective }))
  const b = browse(page)
  await signInOnThePage(b)
  await startFromFindMachines(b)
  await stepOneChecks(b)
  await stepTwo(b)
  await stepThree(b)
  const { box, keysBefore } = await installIntoThrowAwayFolder(b)
  await failedInstall(b)
  await installAndFollow(b, box)
  await machinePage(b)
  await removeIt(b, box, keysBefore)
  check('no script errors and no policy violations', errors.length === 0 && (await page.evaluate(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  root.child.kill()
  sshd.child.kill()
}
finish()
