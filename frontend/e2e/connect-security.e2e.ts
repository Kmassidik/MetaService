// End-to-end test of the security baseline in Add a machine (Check step), in a real browser against a real Root. The other computer is the pretend Debian behind a real
// OpenSSH server on loopback (contract/root_tests/fakes/fake_linux.py); what its security look prints is written to its security.txt, so every case is a file.
// Needs: the Root build (`swift build`), Google Chrome (or CHROME_PATH), /usr/sbin/sshd, python3, `bun install` and `bun run build` in frontend/. Run: bun e2e/connect-security.e2e.ts
import { spawn } from 'node:child_process'
import { appendFileSync, writeFileSync } from 'node:fs'
import { userInfo } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline'
import puppeteer from 'puppeteer-core'
import { ADMIN, createAdmin } from './support/admin.ts'
import { check, finish } from './support/check.ts'
import { readRecord, textField } from './support/json.ts'
import { chromePath, repo } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'
import { SCAN_PREFIX, scanSettings, startRoot } from './support/root.ts'

const SETUP_TOKEN = 'e2e-setup-token-0123456789abcdef'
const SHORT_WAIT_MS = 10000
const STEP_WAIT_MS = 20000
const VERDICT = /things? to fix before|All \d+ checks passed|Ready to add|cannot be added/
const BLOCK = 'dialog[open] section[aria-label="Security baseline"]'
const ROWS = `${BLOCK} li[data-check]`
const FRESH = 'password_login=yes\nban_tool=not_running\nfirewall=no\nauto_updates=no\nhas_key_login=yes\npending_updates=4\n'
const NO_KEY = 'password_login=yes\nban_tool=not_running\nfirewall=no\nauto_updates=no\nhas_key_login=no\npending_updates=0\n'
const HOSTILE = 'password_login=<img src=x onerror=alert(1)>\nban_tool=<script>alert(1)</script>\nfirewall=\u001b[31myes\nhas_key_login=no\n'
const DESKTOP = { width: 1280, height: 900 }
const PHONE = { width: 390, height: 844 }
const HARDEN_SUMMARY = 'Harden this machine (needs sudo, you run it)'

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

const answer = (text: string): void => writeFileSync(join(fake.dir, 'security.txt'), text)

async function waitForDialog(b: Browse, pattern: RegExp): Promise<void> {
  await b.until((source) => new RegExp(source, 'i').test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout: STEP_WAIT_MS }, pattern.source)
}

/** Sign in, Find machines, Add on a row, then the pretend computer's address, its host key and the key login: the path to the Check step. */
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

interface RowView { id: string; state: string; text: string }
const readBaseline = (b: Browse): Promise<RowView[]> =>
  b.page.$$eval(ROWS, (items) => items.map((item) => ({ id: item.getAttribute('data-check') ?? '', state: item.getAttribute('data-state') ?? '', text: (item as HTMLElement).innerText.replace(/\s+/g, ' ').trim() })))

/** The dialog scrolls, so a picture of the block is taken with the block at the top of the view. */
async function shotOfBlock(b: Browse, name: `${string}.png`): Promise<void> {
  await b.page.$eval(BLOCK, (node) => node.scrollIntoView({ block: 'start' }))
  await b.shot(name)
}

const noSideways = (b: Browse): Promise<boolean> =>
  b.run(() => {
    const dialog = document.querySelector<HTMLElement>('dialog[open]')
    return document.documentElement.scrollWidth <= window.innerWidth && (dialog?.scrollWidth ?? 0) <= (dialog?.clientWidth ?? 0) + 1
  })

async function warningBaseline(b: Browse): Promise<void> {
  const rows = await readBaseline(b)
  check('the block lists the five checks in the Security page order, none of them about the helper', rows.map((row) => row.id).join() === ['password_login', 'ban_tool', 'firewall', 'auto_updates', 'pending_updates'].map((id) => `security-${id}`).join(), rows.map((row) => row.id).join())
  check('a fresh machine shows five warnings, each with its plain line',
    rows.every((row) => row.state === 'warning') && /Anyone on the internet can keep guessing it/.test(rows[0]?.text ?? '') && /No ban tool/.test(rows[1]?.text ?? '') && /The firewall is off/.test(rows[2]?.text ?? '') && /Security fixes wait/.test(rows[3]?.text ?? '') && /4 security updates are waiting/.test(rows[4]?.text ?? ''), rows.map((row) => row.text).join(' | '))
  const text = await b.dialogText()
  check('the sentence says the install is not held back', text.includes('You can install now and harden afterwards: the Security page keeps showing these rows.'))
  check('no red line when a key is installed', (await b.page.$('[data-testid="no-key"]')) === null)
  check('the harden box is folded away at first', await b.page.$eval('[data-testid="harden-box"]', (node) => !(node as HTMLDetailsElement).open))
  check('the block comes after the cards and has its title', text.toLowerCase().indexOf('security baseline') > text.toLowerCase().indexOf('port 9101'), text.slice(0, 200))
  await shotOfBlock(b, 'connect-security-desktop.png')
}

async function hardenBox(b: Browse): Promise<void> {
  await b.page.click('[data-testid="harden-box"] summary')
  const opened = await b.page.$eval('[data-testid="harden-box"]', (node) => (node as HTMLDetailsElement).open)
  const text = await b.page.$eval('[data-testid="harden-box"]', (node) => (node as HTMLElement).innerText)
  check('the title says it needs sudo and that you run it', opened && text.includes(HARDEN_SUMMARY))
  check('the safety words are there: a second SSH window, and the undo after 5 minutes', /second SSH window/.test(text) && /undoes itself after 5 minutes unless you confirm/.test(text), text)
  const commands = await b.page.$$eval('[data-testid="harden-box"] code', (nodes) => nodes.map((node) => node.textContent ?? ''))
  check('the commands are the Linux script: check, apply with the key-login confirmation, confirm', commands.join(' | ') === './harden-linux.sh check | sudo ./harden-linux.sh apply --confirm-key-login | sudo ./harden-linux.sh confirm', commands.join(' | '))
  const buttons = await b.page.$$('[data-testid="harden-box"] button.copy')
  check('every command has its own Copy button', buttons.length === commands.length && commands.length === 3)
  await buttons[1]?.click()
  await b.until(() => /Copied|Could not copy/.test(document.querySelector('[data-testid="harden-box"] li:nth-child(2) button.copy')?.textContent ?? ''), { timeout: SHORT_WAIT_MS })
  check('the button says Copied', (await buttons[1]?.evaluate((node) => node.textContent)) === 'Copied')
  const copied = await b.run(() => (window as unknown as Record<string, string>).__copied)
  check('the second button copied exactly the apply command', copied === 'sudo ./harden-linux.sh apply --confirm-key-login', copied)
  await b.run(() => { (window as unknown as Record<string, boolean>).__reject = true })
  await buttons[0]?.click()
  await b.until(() => document.querySelector('[data-testid="harden-box"] li:nth-child(1) button.copy')?.textContent === 'Could not copy', { timeout: SHORT_WAIT_MS })
  check('when the browser refuses to copy the button says so and nothing else happens', true)
  await shotOfBlock(b, 'connect-security-harden.png')
}

async function phone(b: Browse): Promise<void> {
  await b.page.setViewport(PHONE)
  check('on a phone there is no sideways scroll, with the harden box open', await noSideways(b))
  await shotOfBlock(b, 'connect-security-phone.png')
  await b.page.setViewport(DESKTOP)
}

async function noKey(b: Browse): Promise<void> {
  answer(NO_KEY)
  await b.click('Check another')
  await reachTheCheck(b, false)
  const line = await b.page.$eval('[data-testid="no-key"]', (node) => ({ text: (node as HTMLElement).innerText, color: getComputedStyle(node).color, role: node.getAttribute('role') })).catch(() => null)
  check('with no key the RED line says not to turn off password login yet', line?.text === 'No SSH key is installed for this user: do not turn off password login yet' && line.role === 'alert', JSON.stringify(line))
  check('the line is red (the danger colour is not the text colour)', line !== null && /^rgb\((2[0-5]\d|1[5-9]\d), /.test(line.color), line?.color)
  check('0 pending updates is a tick', (await readBaseline(b)).find((row) => row.id === 'security-pending_updates')?.state === 'ok')
  await shotOfBlock(b, 'connect-security-nokey.png')
}

async function hostile(b: Browse): Promise<void> {
  answer(HOSTILE)
  await b.click('Check another')
  await reachTheCheck(b, false)
  const rows = await readBaseline(b)
  const html = await b.page.$eval(BLOCK, (node) => node.innerHTML)
  check('hostile output is shown as nothing: unknown rows, no markup, no script', rows.length === 5 && rows.every((row) => row.state === 'unknown') && !/<img|<script|onerror|\u001b/.test(html) && !/alert\(/.test(html))
  check('the sentence for unknown is in this step\'s own words', rows.every((row) => /Could not be read from here/.test(row.text)))
  check('even then the red line shows what the machine said about keys', (await b.page.$('[data-testid="no-key"]')) !== null)
}

try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|422|502)/.test(message.text()) && errors.push(message.text()))
  // The clipboard is not available to a headless page; this stand-in keeps what Copy wrote, and refuses when asked to.
  await page.evaluateOnNewDocument(() => {
    const clipboard = { writeText: async (text: string) => { if ((window as unknown as Record<string, boolean>).__reject) throw new Error('refused'); (window as unknown as Record<string, string>).__copied = text } }
    Object.defineProperty(navigator, 'clipboard', { value: clipboard })
  })
  page.on('dialog', (dialog) => { errors.push(`a script dialog opened: ${dialog.message()}`); void dialog.dismiss() })
  const b = browse(page)
  answer(FRESH)
  await reachTheCheck(b, true)
  await warningBaseline(b)
  await hardenBox(b)
  await phone(b)
  await noKey(b)
  await hostile(b)
  check('no script errors and no script dialogs', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  root.child.kill()
  python.stdin.end('\n')
}
finish()
