// The button rules for Start, Stop and Delete, proved in a real browser against the stand-in Root (slow, refusing or silent on command):
// five quick clicks or key presses send one request, the button says it is busy, a refusal shows next to the button and frees it, a silent Root frees it after the timeout,
// the success line goes away by itself, and Escape does not close a Delete dialog while it is working.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import type { StandIn } from './standin.ts'

const VMS_TAB = '#/machines/details?id=studio&tab=vms'
const VM_PAGE = '#/machines/details?id=studio&vm=vm2'
const SLOW_MS = 800
const RAPID_CLICKS = 5
const SEEN_BUSY_AFTER_MS = 250
const SETTLE_MS = 1600
const SUCCESS_LINE_MIN_MS = 1500
const SUCCESS_LINE_MAX_MS = 3500
/** The panel gives up on a silent Root after 30 s; the test waits a little longer. */
const SILENT_ROOT_WAIT_MS = 31_500
const SHORT_WAIT_MS = 8000
const REFUSAL = 'No room on that machine'
const TIMEOUT_TEXT = 'The server did not answer in time. It may still be working: check the list, then try again.'
const VM_REQUEST = /\/api\/machines\/[^/]+\/workloads\/[^/]+\/(start|stop|delete)$/
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }

interface ButtonView {
  found: boolean
  disabled: boolean
  ariaBusy: string | null
  /** The small line right next to the button. */
  line: string
  hasSpinner: boolean
}

/** Counts the calls the page makes to start, stop or delete a VM. */
function watchVmRequests(page: Page) {
  let count = 0
  page.on('request', (request) => {
    if (request.method() === 'POST' && VM_REQUEST.test(new URL(request.url()).pathname)) count += 1
  })
  return { count: () => count, clear: () => { count = 0 } }
}

type Watch = ReturnType<typeof watchVmRequests>

/** Opens a page with the stand-in back at its start. */
async function fresh(b: Browse, standin: StandIn, hash: string): Promise<void> {
  standin.reset()
  await b.page.goto('about:blank')
  await b.page.goto(`${standin.base}/${hash}`, { waitUntil: 'networkidle0' })
}

const buttonView = (b: Browse, text: string, nth = 0): Promise<ButtonView> =>
  b.run((wanted, index) => {
    const scope = document.querySelector('dialog[open]') ?? document
    const button = [...scope.querySelectorAll('button')].filter((entry) => entry.textContent?.trim() === wanted && entry.getClientRects().length > 0)[index]
    if (!button) return { found: false, disabled: false, ariaBusy: null, line: '', hasSpinner: false }
    return {
      found: true,
      disabled: button.disabled,
      ariaBusy: button.getAttribute('aria-busy'),
      line: button.parentElement?.querySelector('.aline')?.textContent?.trim() ?? '',
      hasSpinner: button.querySelector('.btn-spin') !== null,
    }
  }, text, nth)

const waitForButton = (b: Browse, text: string): Promise<unknown> =>
  b.until((wanted) => [...(document.querySelector('dialog[open]') ?? document).querySelectorAll('button')].some((entry) => entry.textContent?.trim() === wanted && entry.getClientRects().length > 0), { timeout: SHORT_WAIT_MS }, text)

/** Clicks the button with this text `count` times as fast as the browser can. */
async function burst(b: Browse, text: string, count: number, nth = 0): Promise<void> {
  const at = await b.run((wanted, index) => {
    const scope = document.querySelector('dialog[open]') ?? document
    const button = [...scope.querySelectorAll('button')].filter((entry) => entry.textContent?.trim() === wanted && entry.getClientRects().length > 0)[index]
    if (!button) return null
    button.scrollIntoView({ block: 'center' })
    const box = button.getBoundingClientRect()
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 }
  }, text, nth)
  if (!at) throw new Error(`there is no button "${text}"`)
  await b.page.mouse.click(at.x, at.y, { count })
}

const dialogIsOpen = (b: Browse) => b.run(() => document.querySelector('dialog[open]') !== null)

async function openTable(b: Browse): Promise<void> {
  await b.click('Table')
  await b.page.waitForSelector('table.restable')
}

async function oneRequestAndBusy(b: Browse, standin: StandIn, watch: Watch, name: string, idle: string, busy: string, expectedCall: string, shotName: `${string}.png`): Promise<void> {
  await waitForButton(b, idle)
  watch.clear()
  standin.behaviour.delayMs = SLOW_MS
  await burst(b, idle, RAPID_CLICKS)
  await wait(SEEN_BUSY_AFTER_MS)
  const view = await buttonView(b, busy)
  check(`${name}: while it works the button says "${busy}", is disabled, aria-busy and has a spinner`, view.found && view.disabled && view.ariaBusy === 'true' && view.hasSpinner, JSON.stringify(view))
  await b.shot(shotName)
  await wait(SETTLE_MS)
  check(`${name}: ${RAPID_CLICKS} rapid clicks send exactly 1 request`, watch.count() === 1 && standin.calls.join() === expectedCall, `page ${watch.count()}, root ${standin.calls.join()}`)
}

export async function startAndStopSendOneRequest(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await fresh(b, standin, VMS_TAB)
  await openTable(b)
  await oneRequestAndBusy(b, standin, watch, 'Start (table)', 'Start', 'Starting…', 'start vm2', 'actions-start-busy.png')
  await fresh(b, standin, VMS_TAB)
  await openTable(b)
  await oneRequestAndBusy(b, standin, watch, 'Stop (table)', 'Stop', 'Stopping…', 'stop vm1', 'actions-stop-busy.png')
}

export async function keysSendOneRequest(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await fresh(b, standin, VMS_TAB)
  await openTable(b)
  await waitForButton(b, 'Start')
  watch.clear()
  standin.behaviour.delayMs = SLOW_MS
  await b.run(() => [...document.querySelectorAll('button')].find((entry) => entry.textContent?.trim() === 'Start')?.focus())
  for (let press = 0; press < RAPID_CLICKS; press++) await b.page.keyboard.press('Enter')
  for (let press = 0; press < RAPID_CLICKS; press++) await b.page.keyboard.press('Space')
  await wait(SETTLE_MS)
  check('Start: Enter and Space pressed five times each send exactly 1 request', watch.count() === 1, `${watch.count()}`)
}

export async function refusalShowsNextToTheButton(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await fresh(b, standin, VMS_TAB)
  await openTable(b)
  await waitForButton(b, 'Stop')
  watch.clear()
  standin.behaviour.refuseWith = REFUSAL
  await burst(b, 'Stop', 1)
  await b.until(() => document.querySelector('.abtn .aline.bad') !== null, { timeout: SHORT_WAIT_MS })
  const view = await buttonView(b, 'Stop')
  check('a refused Stop shows the reason next to the button and the button works again', view.found && !view.disabled && view.ariaBusy === 'false' && view.line === REFUSAL, JSON.stringify(view))
  check('the refusal line is a polite status message', await b.run(() => document.querySelector('.abtn .aline.bad')?.getAttribute('role') === 'status' && document.querySelector('.abtn .aline.bad')?.getAttribute('aria-live') === 'polite'))
  await b.shot('actions-stop-failed.png')
  standin.behaviour.refuseWith = null
  await burst(b, 'Stop', 1)
  await b.until(() => ![...document.querySelectorAll('button')].some((entry) => entry.textContent?.trim() === 'Stop'), { timeout: SHORT_WAIT_MS })
  check('after a refusal a second try goes through', watch.count() === 2 && standin.calls.join() === 'stop vm1,stop vm1', `${watch.count()} ${standin.calls.join()}`)
}

export async function successLineGoesAway(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, VM_PAGE)
  await waitForButton(b, 'Start')
  await burst(b, 'Start', 1)
  await b.until(() => document.querySelector('.abtn .aline')?.textContent?.trim() === 'Started', { timeout: SHORT_WAIT_MS })
  const shownAt = Date.now()
  await b.until(() => (document.querySelector('.abtn .aline')?.textContent?.trim() ?? '') === '', { timeout: SHORT_WAIT_MS })
  const shownFor = Date.now() - shownAt
  check(`the "Started" line next to the button goes away by itself after about 2 s (${shownFor} ms)`, shownFor >= SUCCESS_LINE_MIN_MS && shownFor <= SUCCESS_LINE_MAX_MS)
}

export async function silentRootFreesTheButton(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await fresh(b, standin, VM_PAGE)
  await waitForButton(b, 'Start')
  watch.clear()
  standin.behaviour.hang = true
  await burst(b, 'Start', RAPID_CLICKS)
  await wait(SETTLE_MS)
  const busy = await buttonView(b, 'Starting…')
  check('a silent Root keeps the button busy at first', busy.found && busy.disabled && busy.ariaBusy === 'true')
  await wait(SILENT_ROOT_WAIT_MS)
  const freed = await buttonView(b, 'Start')
  check('after the timeout the button works again and says the server did not answer', freed.found && !freed.disabled && freed.line === TIMEOUT_TEXT, JSON.stringify(freed))
  check('the hung Start sent exactly 1 request', watch.count() === 1, `${watch.count()}`)
}

async function openDeleteDialog(b: Browse): Promise<void> {
  await openTable(b)
  await waitForButton(b, 'Delete')
  await burst(b, 'Delete', 1)
  await b.page.waitForSelector('dialog[open]')
}

export async function deleteStaysOpenWhileWorking(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await fresh(b, standin, VMS_TAB)
  await openDeleteDialog(b)
  watch.clear()
  standin.behaviour.delayMs = SLOW_MS
  await burst(b, 'Back up and delete', RAPID_CLICKS)
  await wait(SEEN_BUSY_AFTER_MS)
  const confirm = await buttonView(b, 'Deleting…')
  check('Delete confirm: while it works the button says "Deleting…", is disabled and aria-busy', confirm.found && confirm.disabled && confirm.ariaBusy === 'true', JSON.stringify(confirm))
  check('Delete confirm: "Keep it" is switched off and the dialog says it is still working', (await buttonView(b, 'Keep it')).disabled && (await b.dialogText()).includes('Still working'))
  await b.page.keyboard.press('Escape')
  await b.page.mouse.click(2, 2)
  await wait(100)
  check('Escape and a click on the backdrop do not close the dialog while it works', await dialogIsOpen(b))
  await b.shot('actions-delete-busy.png')
  await wait(SETTLE_MS)
  check('Delete confirm: five rapid clicks send exactly 1 request', watch.count() === 1 && standin.calls.join() === 'delete vm1', `page ${watch.count()}, root ${standin.calls.join()}`)
  check('the dialog closes by itself when the request ends', !(await dialogIsOpen(b)))
}

export async function deleteRefusalKeepsTheDialog(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, VMS_TAB)
  await openDeleteDialog(b)
  standin.behaviour.refuseWith = REFUSAL
  await burst(b, 'Back up and delete', 1)
  await b.until(() => document.querySelector('dialog[open] .aline.bad') !== null, { timeout: SHORT_WAIT_MS })
  const view = await buttonView(b, 'Back up and delete')
  check('a refused Delete keeps the dialog, shows the reason next to the button and frees it', view.found && !view.disabled && view.ariaBusy === 'false' && view.line === REFUSAL, JSON.stringify(view))
  await b.shot('actions-delete-failed.png')
  await b.page.keyboard.press('Escape')
  await wait(200)
  check('once the request has ended Escape closes the dialog again', !(await dialogIsOpen(b)))
}

export async function onAPhone(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  await fresh(b, standin, VM_PAGE)
  await waitForButton(b, 'Start')
  standin.behaviour.delayMs = SLOW_MS
  await burst(b, 'Start', 1)
  await wait(SEEN_BUSY_AFTER_MS)
  check('phone: no sideways scrolling while a button is busy', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await b.shot('actions-start-busy-phone.png')
  await wait(SETTLE_MS)
  standin.behaviour.refuseWith = REFUSAL
  await waitForButton(b, 'Stop')
  await burst(b, 'Stop', 1)
  await b.until(() => document.querySelector('.abtn .aline.bad') !== null, { timeout: SHORT_WAIT_MS })
  check('phone: the refusal line fits the screen', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await b.shot('actions-stop-failed-phone.png')
  await b.page.setViewport(DESKTOP)
}

export { watchVmRequests }
