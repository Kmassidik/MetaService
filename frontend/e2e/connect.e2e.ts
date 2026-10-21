// End-to-end test of Add a machine (a computer found on the network, then looked at, installed over SSH, watched, and removed) in a real browser against a real Root
// and a real OpenSSH server on loopback. The way in is Find machines: scan, then Add on a row. There is no other button.
// Needs: the Root build and the macOS Agent build (`swift build`), Google Chrome (or CHROME_PATH), /usr/sbin/sshd, and `bun install` in frontend/. Run: bun e2e/connect.e2e.ts
import { appendFileSync, existsSync, mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir, userInfo } from 'node:os'
import { dirname, join } from 'node:path'
import puppeteer from 'puppeteer-core'
import { ADMIN, createAdmin } from './support/admin.ts'
import { check, finish } from './support/check.ts'
import { readRecord, textField } from './support/json.ts'
import { freePort } from './support/net.ts'
import { chromePath } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'
import { SCAN_PREFIX, scanSettings, startRoot } from './support/root.ts'
import { startSshd } from './support/sshd.ts'
import { openMachine, openTab } from './machine/steps.ts'

const SETUP_TOKEN = 'e2e-setup-token-0123456789abcdef'
const KEY_LINE = 'dialog[open] [aria-label="Command that lets MetaService in"]'
const NO_SSH_PORT = '1'
const NAME = 'e2e-remote'
const FOUND_ADDRESS = `${SCAN_PREFIX}.40`
const SHORT_WAIT_MS = 10000
const STEP_WAIT_MS = 20000
const INSTALL_WAIT_MS = 120000
const ONLINE_WAIT_MS = 60000
const SCREEN_WIDTH_PX = 160
const POINTER_VISIBLE = 200
const ALL_CHECKS = 11
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
  check('before the key is allowed the login is refused and said plainly', /refused/i.test(await b.dialogText()) && /Looks good/.test(await b.dialogText()) === false)
  appendFileSync(sshd.authorized, publicKey + '\n')
}

async function stepThree(b: Browse): Promise<void> {
  await b.click('Log in and check')
  await waitForDialog(b, /Looks good/)
  const result = await b.dialogText()
  check('step 3 says what the computer is', /macOS/.test(result) && /Apple/.test(result) && new RegExp(userInfo().username).test(result))
  const rows = await b.page.$$eval('dialog[open] .checks li', (items) => items.map((item) => item instanceof HTMLElement ? item.innerText.replace(/\s+/g, ' ').trim() : ''))
  check('step 3 lists every check, with the program for this system found',
    rows.length === ALL_CHECKS && rows.some((row) => /^✓ MetaService program/.test(row)) && rows.some((row) => /^✓ Apple's container tool/.test(row)) && rows.some((row) => /^✓ The parent can be reached/.test(row)), rows.join(' | '))
  check('step 3 says where MetaService would go, in plain words', /In a folder of that user/.test(result))
  check('Add machine is on, because everything that must pass passed', !(await b.isDisabled('Add machine')))
  await b.shot('connect-result.png')
  await b.click('Check another')
  await b.page.waitForSelector('dialog[open] #connect-host')
  check('Check another goes back to step 1', /Look at it/.test(await b.dialogText()))
  await reachResult(b)
}

/** The path to step 3 again, from step 1. */
async function reachResult(b: Browse): Promise<void> {
  await b.type('#connect-host', '127.0.0.1')
  await b.type('#connect-port', String(sshd.port))
  await b.click('Look at it')
  await waitForDialog(b, /Found a computer at/)
  await b.type('#connect-user', userInfo().username)
  await b.click('Log in and check')
  await waitForDialog(b, /Looks good/)
}

/** What will change, with the advanced choices pointing at throw-away folders, so nothing outside them is touched. Returns the box folder and the keys as they were. */
async function installIntoThrowAwayFolder(b: Browse): Promise<{ box: string; keysBefore: string }> {
  const box = join(mkdtempSync(join(tmpdir(), 'ms-e2e-box-')), 'metaservice-box')
  const keysBefore = readFileSync(sshd.authorized, 'utf8')
  await b.click('Add machine')
  await waitForDialog(b, /What will change on/)
  await b.page.waitForSelector('dialog[open] ol.plan')
  const plan = await b.page.$$eval('dialog[open] ol.plan > li', (items) => items.map((item) => item.querySelector('strong')?.textContent ?? ''))
  check('What will change lists every step in plain words', plan.join(' | ') === "Make the box folder | Copy the MetaService program | Enroll it with the parent | Start the program | Allow the parent's tunnel | Write the record", plan.join(' | '))
  check('it says the key line is the only change to a file that exists', /ONE line/.test(await b.dialogText()) && /only change to a file that already exists/.test(await b.dialogText()))
  check('Install is off until the machine has a valid name', await b.run(() => !document.querySelector<HTMLButtonElement>('dialog[open] button[type=submit]')?.disabled))
  await b.type('#remote-name', 'Bad Name')
  check('a bad machine name turns Install off and says why', /lowercase letters/i.test(await b.dialogText()) && await b.run(() => document.querySelector<HTMLButtonElement>('dialog[open] button[type=submit]')?.disabled ?? false))
  await b.type('#remote-name', NAME)
  check('the screen choice is off until it is ticked', await b.run(() => ![...document.querySelectorAll<HTMLLabelElement>('dialog[open] label.check')].find((label) => /see and control/.test(label.textContent ?? ''))?.querySelector('input')?.checked))
  await b.run(() => [...document.querySelectorAll<HTMLLabelElement>('dialog[open] label.check')].find((label) => /see and control/.test(label.textContent ?? ''))?.querySelector('input')?.click())
  await b.until(() => /take its mouse and keyboard/.test(document.querySelector<HTMLElement>('dialog[open] ol.plan')?.innerText ?? ''), { timeout: SHORT_WAIT_MS })
  check('ticking it adds a plain sentence to What will change', true)
  await b.run(() => { const details = document.querySelector<HTMLDetailsElement>('dialog[open] details.advanced'); if (details) details.open = true })
  await b.type('#remote-box', box)
  await b.type('#remote-ssh', dirname(sshd.authorized))
  await b.type('#remote-port', String(await freePort()))
  await b.until((where) => document.querySelector<HTMLElement>('dialog[open] ol.plan')?.innerText.includes(where), { timeout: SHORT_WAIT_MS }, box)
  check('the plan follows the folder that was typed', true)
  await b.shot('connect-plan.png')
  return { box, keysBefore }
}

async function installAndFollow(b: Browse, box: string): Promise<void> {
  await b.click('Install')
  await waitForDialog(b, new RegExp(`Installing ${NAME}`))
  await b.until(() => /is added: it shows in Machines/.test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout: INSTALL_WAIT_MS })
  const steps = await b.page.$$eval('dialog[open] ol[aria-label="Install steps"] li', (items) => items.map((item) => item instanceof HTMLElement ? (item.innerText.replace(/\s+/g, ' ').trim().split(' ')[0] ?? '') : ''))
  check('the install shows every step and ends with all of them done', steps.length === ALL_INSTALL_STEPS && steps.every((mark) => mark === '✓'), steps.join(' '))
  await b.shot('connect-installed.png')
  const keyLines = readFileSync(sshd.authorized, 'utf8').split('\n').filter((line) => line.endsWith(`metaservice-${NAME}`))
  check('the box exists and the one key line was added', existsSync(join(box, 'manifest.json')) && existsSync(join(box, 'bin', 'metaservice-agent')) && keyLines.length === 1)
  check('the one-time token and the install marker are gone', !existsSync(join(box, 'state', 'enroll.token')) && !existsSync(join(box, '.partial')))
  await b.click('Done')
  await b.page.click('aside.side a[href="#/machines"]')
  await b.until((name) => new RegExp(`${name}[\\s\\S]{0,500}(online|busy)`, 'i').test(document.body.innerText), { timeout: ONLINE_WAIT_MS }, NAME)
  check('the new machine shows in Machines and is online', true)
}

async function machinePageAndScreen(b: Browse): Promise<void> {
  await openMachine(b, root.base, NAME)
  await openTab(b, 'Environment')
  await b.until(() => /tunnel\s*SSH tunnel · connected/i.test(document.body.innerText), { timeout: 30000 })
  check('the Environment tab says its SSH tunnel is connected, and where the helper is installed', /helper folder\s*[^\n]*metaservice-box/i.test(await b.text()))
  await b.shot('connect-machine-page.png')
  await openTab(b, 'Overview')
  // The screen: view only first, control only after the second, confirmed step, and the picture follows the pointer.
  await b.click('Open screen')
  await waitForDialog(b, new RegExp(`Screen of ${NAME}`))
  await b.until((width) => document.querySelector<HTMLCanvasElement>('dialog[open] canvas')?.width === width, { timeout: STEP_WAIT_MS }, SCREEN_WIDTH_PX)
  check('the screen opens as view only and a picture is drawn', /View only/.test(await b.dialogText()))
  const centreRed = () => b.run(() => {
    const canvas = document.querySelector<HTMLCanvasElement>('dialog[open] canvas')
    const pixel = canvas?.getContext('2d')?.getImageData(Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1).data[0]
    return pixel ?? -1
  })
  check('before control the centre is the plain background, not the pointer', (await centreRed()) < POINTER_VISIBLE)
  await b.click('Take control')
  check('control needs a confirm that names the computer', /Everything you type goes to that computer/.test(await b.dialogText()) && new RegExp(NAME).test(await b.dialogText()))
  await b.click('Yes, take control')
  await b.until((name) => new RegExp(`You are controlling ${name}`).test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout: SHORT_WAIT_MS }, NAME)
  check('the banner says the computer is being controlled', true)
  const area = await (await b.page.$('dialog[open] canvas'))?.boundingBox()
  if (!area) throw new Error('the screen picture has no size')
  await b.page.mouse.move(area.x + area.width / 2, area.y + area.height / 2)
  await b.until((visible) => {
    const canvas = document.querySelector<HTMLCanvasElement>('dialog[open] canvas')
    const pixel = canvas?.getContext('2d')?.getImageData(Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1).data[0]
    return pixel !== undefined && pixel > visible
  }, { timeout: SHORT_WAIT_MS }, POINTER_VISIBLE)
  check('moving the pointer over the picture moves the pointer on the computer', true)
  await b.shot('connect-screen.png')
  await b.click('End')
  await b.until(() => !document.querySelector('dialog[open]'), { timeout: SHORT_WAIT_MS })
  check('End closes the screen', true)
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
  await installAndFollow(b, box)
  await machinePageAndScreen(b)
  await removeIt(b, box, keysBefore)
  check('no script errors and no policy violations', errors.length === 0 && (await page.evaluate(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  root.child.kill()
  sshd.child.kill()
}
finish()
