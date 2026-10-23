// The progress window after Create, in a real browser against the stand-in Root, which plays the parent's create order and the machine's VM list by hand so each step can be looked at:
// the steps follow the order (waiting, creating) and the machine's list (starting) and the app (installing), a made VM offers Open VM, a failed one turns its step red and stays until closed,
// the window closes at any time while the VM goes on being made, and it fits a phone.
// Needs: a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/. No Root, no helper.
// Run: bun e2e/create-progress.e2e.ts   (SHOTS_DIR=<existing folder> to keep screenshots)
import puppeteer from 'puppeteer-core'
import { fresh } from './actions/guard.ts'
import { startStandIn, type StandIn } from './actions/standin.ts'
import { DESKTOP, MACHINE_VMS, PHONE } from './apps/catalog.ts'
import { check, finish } from './support/check.ts'
import { FRAMEWORK, NAME, PROGRESS, choose, imageListArrived } from './support/createVm.ts'
import { wait } from './support/net.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'

const MACHINE = 'studio'
const STEP_WAIT_MS = 15000
const SETTLE_MS = 400
const NO_AUTO_CLOSE_MS = 4500
const FAILURE_REASON = 'no space left on the disk'
const STEPS = `${PROGRESS} [data-step]`

type OrderState = 'queued' | 'running' | 'succeeded' | 'failed'

function order(name: string, state: OrderState, extra: Record<string, unknown> = {}, params: Record<string, string> = {}) {
  return { id: 'ord-progress', type: 'create', machine: MACHINE, workload_id: null, state, created_at: new Date().toISOString(), params: { name, kind: 'vm', ...params }, ...extra }
}

const madeVm = (id: string, name: string, state = 'running') => ({ id, name, kind: 'vm', state, cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: null, bundle_version: null })
const stepStates = (b: Browse) => b.run((selector) => [...document.querySelectorAll(selector)].map((step) => step.classList[0] ?? ''), STEPS)
const stepLabels = (b: Browse) => b.run((selector) => [...document.querySelectorAll(selector)].map((step) => step.textContent?.replace(/[✓!]/g, '').trim() ?? ''), STEPS)
const tagText = (b: Browse) => b.run(() => document.querySelector('dialog[open] [data-progress-tag]')?.textContent?.trim() ?? '')
const untilSteps = (b: Browse, states: string[]) => b.until((selector, wanted) => JSON.stringify([...document.querySelectorAll(selector)].map((step) => step.classList[0] ?? '')) === wanted, { timeout: STEP_WAIT_MS }, STEPS, JSON.stringify(states))
const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
const fitsTheScreen = (b: Browse) => b.run(() => { const box = document.querySelector('dialog[open]')?.getBoundingClientRect(); return box !== undefined && box.left >= 0 && box.right <= window.innerWidth && box.bottom <= window.innerHeight })
const modalIsOpen = (b: Browse) => b.run((selector) => document.querySelector(selector) !== null, PROGRESS)

async function phoneShot(b: Browse, name: `${string}.png`, what: string): Promise<void> {
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS)
  check(`${what}: no sideways scrolling and the window fits the phone`, (await noSideScroll(b)) && (await fitsTheScreen(b)))
  await b.shot(name)
  await b.page.setViewport(DESKTOP)
  await wait(SETTLE_MS)
}

/** Opens the machine's Create VM window, fills the name (and OpenClaw when asked) and presses Create with the parent's order already played. */
async function create(b: Browse, standin: StandIn, name: string, first: ReturnType<typeof order>, app = false): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  standin.script.order = first
  await b.click('＋ New VM')
  await b.page.waitForSelector(FRAMEWORK, { timeout: STEP_WAIT_MS })
  await imageListArrived(b)
  await b.type(NAME, name)
  if (app) await choose(b, FRAMEWORK, 'openclaw')
  await b.click('Create VM')
  await b.page.waitForSelector(PROGRESS, { timeout: STEP_WAIT_MS })
}

async function stepsFollowTheParent(b: Browse, standin: StandIn): Promise<void> {
  await create(b, standin, 'prog-box', order('prog-box', 'queued'))
  check('Create closes its form and the progress window opens on its own, as the only window', (await b.run(() => document.querySelectorAll('dialog[open]').length)) === 1 && (await b.run(() => document.querySelector('form[aria-label="Create VM"]') === null)))
  check('three steps are listed with their real names', JSON.stringify(await stepLabels(b)) === JSON.stringify(['Waiting for the machine', 'Creating', 'Starting']), JSON.stringify(await stepLabels(b)))
  check('a queued order is on the first step, the tag says Creating…', JSON.stringify(await stepStates(b)) === JSON.stringify(['now', 'next', 'next']) && (await tagText(b)) === 'Creating…')
  const head = await b.run((selector) => ({ text: document.querySelector(`${selector}`)?.closest('dialog')?.innerText ?? '', link: document.querySelector<HTMLAnchorElement>('dialog[open] .on a')?.getAttribute('href') ?? '' }), PROGRESS)
  check('the header names the VM, "on <machine>" and links to the machine page', head.text.includes('prog-box') && head.text.includes(`on ${MACHINE}`) && head.link.includes(`machines/details?id=${MACHINE}`), JSON.stringify(head))
  check('the current step shows the panel spinner', await b.run((selector) => document.querySelector(`${selector}.now .btn-spin`) !== null, STEPS))
  await b.shot('progress-working-desktop.png')
  await phoneShot(b, 'progress-working-phone.png', 'working on a phone')
  standin.script.order = order('prog-box', 'running')
  await untilSteps(b, ['done', 'now', 'next'])
  check('when the machine takes the order the second step is current', true)
  standin.script.order = order('prog-box', 'succeeded', { result: { workload_id: 'wl-prog' } })
  await untilSteps(b, ['done', 'done', 'now'])
  check('a made VM that the machine has not listed is on Starting', (await tagText(b)) === 'Creating…')
  standin.putVm(MACHINE, madeVm('wl-prog', 'prog-box'))
  await untilSteps(b, ['done', 'done', 'done'])
  check('once the machine lists it running every step is done and the tag says Ready', (await tagText(b)) === 'Ready')
  const open = await b.run(() => document.querySelector<HTMLAnchorElement>('dialog[open] a.btn.green')?.getAttribute('href') ?? '')
  check('Open VM links to the new VM, and Close is offered too', open.includes('vm=wl-prog') && (await b.dialogText()).includes('Close'), open)
  await b.shot('progress-done-desktop.png')
  await phoneShot(b, 'progress-done-phone.png', 'done on a phone')
  await b.page.click('dialog[open] a.btn.green')
  await b.until(() => document.querySelector('dialog[open]') === null && location.hash.includes('vm=wl-prog'), { timeout: STEP_WAIT_MS })
  check('Open VM closes the window and opens the VM page', true)
}

async function withAnApp(b: Browse, standin: StandIn): Promise<void> {
  await create(b, standin, 'claw-box', order('claw-box', 'running', {}, { app: 'openclaw' }), true)
  check('an app adds a fourth step named after it', JSON.stringify(await stepLabels(b)) === JSON.stringify(['Waiting for the machine', 'Creating', 'Starting', 'Installing OpenClaw']), JSON.stringify(await stepLabels(b)))
  standin.script.order = order('claw-box', 'succeeded', { result: { workload_id: 'wl-claw' } }, { app: 'openclaw' })
  standin.putVm(MACHINE, madeVm('wl-claw', 'claw-box'))
  standin.apps.begin('wl-claw', 'openclaw')
  await untilSteps(b, ['done', 'done', 'done', 'now'])
  check('with the VM running and the app installing the last step is current and the tag still says Creating…', (await tagText(b)) === 'Creating…')
  await b.shot('progress-app-desktop.png')
  standin.apps.finish('wl-claw')
  await untilSteps(b, ['done', 'done', 'done', 'done'])
  check('when the app is ready the window says Ready', (await tagText(b)) === 'Ready')
  standin.apps.failure = 'The installer has no network.'
  standin.putVm(MACHINE, madeVm('wl-claw2', 'claw-box'))
  standin.script.order = order('claw-box', 'succeeded', { result: { workload_id: 'wl-claw2' } }, { app: 'openclaw' })
  standin.apps.begin('wl-claw2', 'openclaw')
  standin.apps.finish('wl-claw2')
  await untilSteps(b, ['done', 'done', 'done', 'failed'])
  check('a failed app install turns the last step red and says why', (await tagText(b)) === 'Failed' && (await b.dialogText()).includes('The installer has no network.'))
}

async function aFailedCreate(b: Browse, standin: StandIn): Promise<void> {
  await create(b, standin, 'bad-box', order('bad-box', 'failed', { finished_at: new Date().toISOString(), result: { error: FAILURE_REASON } }))
  await untilSteps(b, ['done', 'failed', 'next'])
  const text = await b.dialogText()
  check('the failing step is red, the tag says Failed and the reason is in plain words', (await tagText(b)) === 'Failed' && text.includes('No space left on the disk.'), text)
  check('a failed window offers Close and no Open VM', text.includes('Close') && !text.includes('Open VM'))
  await b.shot('progress-failed-desktop.png')
  await phoneShot(b, 'progress-failed-phone.png', 'failed on a phone')
  await wait(NO_AUTO_CLOSE_MS)
  check('a failed window never closes by itself', await modalIsOpen(b))
  await b.click('Close')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: STEP_WAIT_MS })
  check('Close closes it', true)
}

async function closeAnyTime(b: Browse, standin: StandIn): Promise<void> {
  await create(b, standin, 'later-box', order('later-box', 'queued'))
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: STEP_WAIT_MS })
  check('Escape closes the window while the VM is still being made', true)
  await b.until(() => document.querySelector('ul.pending li[data-pending="later-box"]') !== null, { timeout: STEP_WAIT_MS })
  check('the VM goes on behind it: its Creating card is on the page', true)
  await create(b, standin, 'click-box', order('click-box', 'queued'))
  await b.page.mouse.click(4, 4)
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: STEP_WAIT_MS })
  check('a click on the backdrop closes it too', true)
}

const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const b = browse(page)
  await stepsFollowTheParent(b, standin)
  await withAnApp(b, standin)
  await aFailedCreate(b, standin)
  await closeAnyTime(b, standin)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
