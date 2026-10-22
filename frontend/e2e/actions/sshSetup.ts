// The SSH setup block of the SSH keys dialog in a real browser against the stand-in Root: the calm progress line while the helper installs, polling every 3 s (one request at a time, none when idle or closed),
// Ready with the command and Copy, a failure with Try again that sends one retry for five rapid clicks, and that no key is ever shown.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { burst, fresh, openTable, waitForButton } from './guard.ts'
import { BLOB_NEW, DESKTOP, KEY_NEW, KEY_ONE, KEY_TWO, MACHINE_VMS, noSideScroll, openKeys, PHONE, SHORT_WAIT_MS } from './ssh.ts'
import type { StandIn } from './standin.ts'

export const INSTALLING = 'Setting up SSH inside the VM… this takes about a minute the first time.'
export const READY = 'Ready. This key can log in.'
export const PASTE_NOTE = "Paste this in your terminal. It goes through the machine, because the VM's address is private."
export const DEFAULT_NOTE = "Uses the machine's office address. From outside the office, set the machine's SSH address in Environment."
export const OFFICE_COMMAND = 'ssh -J luca@202.0.113.9 root@10.0.0.1'
const FAILURE = 'Could not install openssh-server: the VM has no network.'
const POLL_INTERVAL_MS = 3000
const READY_WAIT_MS = 20_000
const RAPID_CLICKS = 5
const SLOW_MS = 700
const SETTLE_MS = 1600
const QUIET_MS = 4500
const OVERLAP_WATCH_MS = 10_000
const SLOW_POLL_MS = 3500
const KEYS_REQUEST = /\/ssh-keys$/

/** The command in the box of the open dialog, or the empty string. */
export const commandShown = (b: Browse) => b.run(() => document.querySelector('dialog[open] .box code')?.textContent?.trim() ?? '')

const dialogHas = (b: Browse, text: string) => b.until((wanted) => (document.querySelector('dialog[open]') as HTMLElement | null)?.innerText.includes(wanted) === true, { timeout: READY_WAIT_MS }, text)

/** Counts the GETs of the keys list, and the most that were ever in flight at once. */
function watchGets(page: Page) {
  let total = 0
  let inFlight = 0
  let most = 0
  page.on('request', (request) => {
    if (request.method() !== 'GET' || !KEYS_REQUEST.test(new URL(request.url()).pathname)) return
    total += 1
    inFlight += 1
    most = Math.max(most, inFlight)
  })
  const done = (request: { method: () => string; url: () => string }) => {
    if (request.method() === 'GET' && KEYS_REQUEST.test(new URL(request.url()).pathname)) inFlight -= 1
  }
  page.on('requestfinished', done)
  page.on('requestfailed', done)
  return { total: () => total, most: () => most }
}

/** Collects every answer of the SSH-keys routes as text, to prove no key blob is ever sent to the page. */
function collectAnswers(page: Page): string[] {
  const bodies: string[] = []
  page.on('response', (response) => {
    if (new URL(response.url()).pathname.includes('/ssh-keys')) void response.text().then((text) => bodies.push(text), () => undefined)
  })
  return bodies
}

async function installingThenReady(b: Browse, standin: StandIn): Promise<void> {
  const answers = collectAnswers(b.page)
  await fresh(b, standin, MACHINE_VMS)
  standin.sshKeys.installPolls = 2
  await openTable(b)
  await openKeys(b, 'vm1')
  check('no keys and idle: no Ready line and no progress line', !(await b.dialogText()).includes(READY) && !(await b.dialogText()).includes(INSTALLING))
  await b.type('dialog[open] #ssh-key-paste', KEY_NEW)
  await b.click('Add')
  await dialogHas(b, INSTALLING)
  const spinner = await b.run(() => document.querySelector('dialog[open] .progress .btn-spin') !== null)
  check('while installing the calm progress line shows with the panel spinner', spinner)
  check('the key list stays usable while installing: the new key is listed', (await b.dialogText()).includes('new@phone'))
  await b.shot('ssh-setup-installing-desktop.png')
  await waitForButton(b, 'Add')
  await b.type('dialog[open] #ssh-key-paste', KEY_TWO)
  await b.click('Add')
  await b.until(() => document.querySelectorAll('dialog[open] ul.keys li').length === 2, { timeout: SHORT_WAIT_MS })
  check('a second key can be added while installing', (await b.dialogText()).includes('ci-runner'))
  await dialogHas(b, READY)
  const text = await b.dialogText()
  check('it turns to Ready with the command, the paste note and the office-address note', text.includes(PASTE_NOTE) && text.includes(DEFAULT_NOTE) && !text.includes(INSTALLING), text)
  check(`the command box holds ${OFFICE_COMMAND}`, (await commandShown(b)) === OFFICE_COMMAND)
  const link = await b.run(() => document.querySelector<HTMLAnchorElement>('dialog[open] a.link')?.getAttribute('href') ?? '')
  check('the office-address note links to the Environment tab of the machine', link === '#/machines/details?id=studio&tab=environment', link)
  // Headless Chrome refuses real clipboard writes, so the browser's writeText is replaced by a recorder: what Copy hands to the clipboard is what is checked.
  await b.run(() => {
    const record = (text: string) => { (window as unknown as { copiedText: string }).copiedText = text; return Promise.resolve() }
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: record }, configurable: true })
  })
  await b.page.click('dialog[open] .box button[data-tip="Copy command"]')
  await b.until(() => document.querySelector('dialog[open] .box button')?.getAttribute('data-tip') === 'Copied', { timeout: SHORT_WAIT_MS })
  const copied = await b.run(() => (window as unknown as { copiedText?: string }).copiedText ?? '')
  check('Copy says Copied and hands exactly the command to the clipboard', copied === OFFICE_COMMAND, copied)
  await b.shot('ssh-setup-ready-desktop.png')
  const leaked = await b.run((blob) => document.documentElement.innerHTML.includes(blob) || document.body.innerText.includes(blob), BLOB_NEW)
  check('no key blob on the page', !leaked)
  check('no key blob in any answer of the SSH-keys routes', answers.length > 0 && answers.every((body) => !body.includes(BLOB_NEW)), `${answers.length} answers`)
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS / 4)
  check('phone 400px: Ready with the command does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-setup-ready-phone.png')
  await b.page.setViewport(DESKTOP)
}

async function pollsOnlyWhileInstalling(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  standin.sshKeys.installPolls = 1
  await openTable(b)
  await openKeys(b, 'vm1')
  const gets = watchGets(b.page)
  await b.type('dialog[open] #ssh-key-paste', KEY_NEW)
  await b.click('Add')
  await dialogHas(b, READY)
  const atReady = gets.total()
  await wait(QUIET_MS)
  check('once the setup is finished the dialog stops asking', gets.total() === atReady, `${atReady} then ${gets.total()}`)
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })

  await fresh(b, standin, MACHINE_VMS)
  standin.sshKeys.installPolls = 100
  await openTable(b)
  await openKeys(b, 'vm1')
  const idle = watchGets(b.page)
  await b.type('dialog[open] #ssh-key-paste', KEY_NEW)
  await b.click('Add')
  await dialogHas(b, INSTALLING)
  await wait(POLL_INTERVAL_MS + SETTLE_MS)
  check('while installing the dialog asks again about every 3 s', idle.total() >= 1, `${idle.total()}`)
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  const atClose = idle.total()
  await wait(QUIET_MS)
  check('closing the dialog stops the polling', idle.total() === atClose, `${atClose} then ${idle.total()}`)

  await fresh(b, standin, MACHINE_VMS)
  standin.sshKeys.installPolls = 100
  await openTable(b)
  await openKeys(b, 'vm1')
  standin.sshKeys.delayMs = SLOW_POLL_MS
  const slow = watchGets(b.page)
  await b.type('dialog[open] #ssh-key-paste', KEY_NEW)
  await b.click('Add')
  await wait(OVERLAP_WATCH_MS)
  check('answers slower than the interval never overlap: one check at a time', slow.total() >= 1 && slow.most() === 1, `${slow.total()} checks, ${slow.most()} at once`)
  await b.page.keyboard.press('Escape')
}

async function failedThenTryAgain(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  standin.sshKeys.installPolls = 1
  standin.sshKeys.failure = FAILURE
  await openTable(b)
  await openKeys(b, 'vm1')
  await b.type('dialog[open] #ssh-key-paste', KEY_NEW)
  await b.click('Add')
  await dialogHas(b, FAILURE)
  const failed = await b.run(() => ({ buttons: [...document.querySelectorAll('dialog[open] button')].map((button) => button.textContent?.trim()), html: document.querySelector('dialog[open] .failed .message')?.innerHTML ?? '' }))
  check('failed shows the plain message and a Try again button', failed.buttons.includes('Try again') && failed.html === FAILURE, JSON.stringify(failed))
  await b.shot('ssh-setup-failed-desktop.png')
  await b.page.setViewport(PHONE)
  check('phone 400px: the failure does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-setup-failed-phone.png')
  await b.page.setViewport(DESKTOP)
  standin.sshKeys.failure = null
  standin.sshKeys.delayMs = SLOW_MS
  standin.sshKeys.requests.length = 0
  await burst(b, 'Try again', RAPID_CLICKS)
  await wait(SETTLE_MS)
  const retries = standin.sshKeys.requests.filter((request) => request.startsWith('RETRY'))
  check(`${RAPID_CLICKS} rapid Try again clicks send exactly 1 retry`, retries.length === 1, standin.sshKeys.requests.join())
  standin.sshKeys.delayMs = 0
  await dialogHas(b, READY)
  check('after the retry the setup ends in Ready', (await commandShown(b)) === OFFICE_COMMAND)
  await b.page.keyboard.press('Escape')
}

async function installingOnAPhone(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  await fresh(b, standin, MACHINE_VMS)
  standin.sshKeys.installPolls = 100
  await openTable(b)
  await openKeys(b, 'vm1')
  await b.type('dialog[open] #ssh-key-paste', KEY_ONE)
  await b.click('Add')
  await dialogHas(b, INSTALLING)
  check('phone 400px: the progress line does not scroll sideways', await noSideScroll(b))
  await b.shot('ssh-setup-installing-phone.png')
  await b.page.keyboard.press('Escape')
  await b.page.setViewport(DESKTOP)
}

export async function sshSetupWorks(b: Browse, standin: StandIn): Promise<void> {
  await installingThenReady(b, standin)
  await pollsOnlyWhileInstalling(b, standin)
  await failedThenTryAgain(b, standin)
  await installingOnAPhone(b, standin)
}
