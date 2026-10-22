// The button rules for the chat bundle controls (Install chat, Reinstall chat, Update to X, Pin, Roll back) and the Ruvio switch, against the stand-in Root:
// five quick clicks or key presses send one request, the control says it is busy, a refusal shows next to the control on the page where it lives and frees it,
// the switch goes back when the request fails, and the success line goes away by itself.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { buttonView, burst, fresh, openTable, waitForButton } from './guard.ts'
import type { StandIn } from './standin.ts'

const VMS_TAB = '#/machines/details?id=studio&tab=vms'
const MINI_VMS_TAB = '#/machines/details?id=mini&tab=vms'
const STUDIO_ENVIRONMENT = '#/machines/details?id=studio&tab=environment'
const MINI_ENVIRONMENT = '#/machines/details?id=mini&tab=environment'
const VM_PAGE = '#/machines/details?id=studio&vm=vm1'
const SETTINGS = '#/settings'
const SLOW_MS = 800
const RAPID_CLICKS = 5
const SEEN_BUSY_AFTER_MS = 250
const SETTLE_MS = 1600
const SUCCESS_LINE_MIN_MS = 1500
const SUCCESS_LINE_MAX_MS = 3500
const SHORT_WAIT_MS = 8000
const REFUSAL = 'No chat is built on the parent'
const SWITCH = 'button[role=switch]'
const BUNDLE_REQUEST = /\/api\/(machines\/[^/]+\/bundle\/(install|uninstall)|bundles\/(pin|rollback))$/
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }

interface Control {
  name: string
  hash: string
  /** Opens the table of VMs first, where the control lives in it. */
  inTable: boolean
  idle: string
  busy: string
  done: string
  /** What the stand-in Root should have counted. */
  call: string
  shot: `${string}.png`
}

const CONTROLS: Control[] = [
  { name: 'Install chat', hash: VMS_TAB, inTable: true, idle: 'Install chat', busy: 'Installing…', done: 'Installed', call: 'install vm1', shot: 'actions-install-busy.png' },
  { name: 'Reinstall chat', hash: MINI_VMS_TAB, inTable: true, idle: 'Reinstall chat', busy: 'Installing…', done: 'Installed', call: 'install vm4', shot: 'actions-reinstall-busy.png' },
  { name: 'Update to X', hash: STUDIO_ENVIRONMENT, inTable: false, idle: 'Update to 0.4.0', busy: 'Updating…', done: 'Updated', call: 'install studio', shot: 'actions-update-busy.png' },
  { name: 'Pin', hash: SETTINGS, inTable: false, idle: 'Pin', busy: 'Pinning…', done: 'Pinned', call: 'pin 0.3.0', shot: 'actions-pin-busy.png' },
  { name: 'Roll back', hash: SETTINGS, inTable: false, idle: 'Roll back to 0.3.0', busy: 'Rolling back…', done: 'Rolled back', call: 'rollback', shot: 'actions-rollback-busy.png' },
]

function controlNamed(name: string): Control {
  const found = CONTROLS.find((control) => control.name === name)
  if (!found) throw new Error(`there is no control ${name}`)
  return found
}

/** Counts the calls the page makes to install, uninstall, pin or roll back. */
export function watchBundleRequests(page: Page) {
  let count = 0
  page.on('request', (request) => {
    if (request.method() === 'POST' && BUNDLE_REQUEST.test(new URL(request.url()).pathname)) count += 1
  })
  return { count: () => count, clear: () => { count = 0 } }
}

type Watch = ReturnType<typeof watchBundleRequests>

async function openControl(b: Browse, standin: StandIn, control: Control): Promise<void> {
  await fresh(b, standin, control.hash)
  if (control.inTable) await openTable(b)
  await waitForButton(b, control.idle)
}

interface SwitchView {
  found: boolean
  on: boolean
  disabled: boolean
  ariaBusy: string | null
  /** The words next to the switch: "Saving…", the success text, or the failure. */
  words: string
}

const switchView = (b: Browse): Promise<SwitchView> =>
  b.run((selector) => {
    const control = document.querySelector<HTMLButtonElement>(selector)
    if (!control) return { found: false, on: false, disabled: false, ariaBusy: null, words: '' }
    const note = control.parentElement?.querySelector('.what')
    const words = [note?.querySelector('.saving')?.textContent?.trim() ?? '', note?.querySelector('.aline')?.textContent?.trim() ?? ''].join('').trim()
    return { found: true, on: control.getAttribute('aria-checked') === 'true', disabled: control.disabled, ariaBusy: control.getAttribute('aria-busy'), words }
  }, SWITCH)

async function openSwitch(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MINI_ENVIRONMENT)
  await b.page.waitForSelector(`${SWITCH}:not([disabled])`, { timeout: SHORT_WAIT_MS })
}

export async function fiveClicksSendOneRequest(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  for (const control of CONTROLS) {
    await openControl(b, standin, control)
    watch.clear()
    standin.behaviour.delayMs = SLOW_MS
    await burst(b, control.idle, RAPID_CLICKS)
    await wait(SEEN_BUSY_AFTER_MS)
    const view = await buttonView(b, control.busy)
    check(`${control.name}: while it works the button says "${control.busy}", is disabled, aria-busy and has a spinner`, view.found && view.disabled && view.ariaBusy === 'true' && view.hasSpinner, JSON.stringify(view))
    await b.shot(control.shot)
    await wait(SETTLE_MS)
    check(`${control.name}: ${RAPID_CLICKS} rapid clicks send exactly 1 request`, watch.count() === 1 && standin.calls.join() === control.call, `page ${watch.count()}, root ${standin.calls.join()}`)
  }
}

export async function keysSendOneRequest(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await openControl(b, standin, controlNamed('Pin'))
  watch.clear()
  standin.behaviour.delayMs = SLOW_MS
  await b.run(() => [...document.querySelectorAll('button')].find((entry) => entry.textContent?.trim() === 'Pin')?.focus())
  for (let press = 0; press < RAPID_CLICKS; press++) await b.page.keyboard.press('Enter')
  for (let press = 0; press < RAPID_CLICKS; press++) await b.page.keyboard.press('Space')
  await wait(SETTLE_MS)
  check('Pin: Enter and Space pressed five times each send exactly 1 request', watch.count() === 1, `${watch.count()}`)
}

export async function refusalShowsNextToTheControl(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  for (const control of CONTROLS) {
    await openControl(b, standin, control)
    watch.clear()
    standin.behaviour.refuseWith = REFUSAL
    await burst(b, control.idle, 1)
    await b.until(() => document.querySelector('.aline.bad') !== null, { timeout: SHORT_WAIT_MS })
    const view = await buttonView(b, control.idle)
    check(`${control.name}: a refusal shows the reason next to the button and the button works again`, view.found && !view.disabled && view.ariaBusy === 'false' && view.line === REFUSAL, JSON.stringify(view))
    if (control.name === 'Pin') await b.shot('actions-pin-failed.png')
    standin.behaviour.refuseWith = null
    await burst(b, control.idle, 1)
    await wait(SETTLE_MS)
    check(`${control.name}: after a refusal a second try goes through`, watch.count() === 2 && standin.calls.join() === `${control.call},${control.call}`, `${watch.count()} ${standin.calls.join()}`)
  }
}

export async function switchSendsOneRequest(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await openSwitch(b, standin)
  watch.clear()
  standin.behaviour.delayMs = SLOW_MS
  await b.page.click(SWITCH, { count: RAPID_CLICKS })
  await wait(SEEN_BUSY_AFTER_MS)
  const busy = await switchView(b)
  check('Ruvio switch: while it saves it is disabled, aria-busy, already shows the new position and says "Saving…"', busy.found && busy.disabled && busy.ariaBusy === 'true' && busy.on && busy.words === 'Saving…', JSON.stringify(busy))
  await b.shot('actions-ruvio-saving.png')
  await wait(SETTLE_MS)
  check(`Ruvio switch: ${RAPID_CLICKS} rapid clicks send exactly 1 request`, watch.count() === 1 && standin.calls.join() === 'install mini', `page ${watch.count()}, root ${standin.calls.join()}`)
  const after = await switchView(b)
  check('Ruvio switch: after it saved it is on and says "Saved"', after.on && !after.disabled && after.words === 'Saved', JSON.stringify(after))
  const shownAt = Date.now()
  await b.until((selector) => (document.querySelector(selector)?.parentElement?.querySelector('.what .aline')?.textContent?.trim() ?? '') === '', { timeout: SHORT_WAIT_MS }, SWITCH)
  const shownFor = Date.now() - shownAt
  check(`Ruvio switch: the "Saved" line goes away by itself after about 2 s (${shownFor} ms)`, shownFor <= SUCCESS_LINE_MAX_MS)
}

export async function switchKeysSendOneRequest(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await openSwitch(b, standin)
  watch.clear()
  standin.behaviour.delayMs = SLOW_MS
  await b.run((selector) => document.querySelector<HTMLButtonElement>(selector)?.focus(), SWITCH)
  for (let press = 0; press < RAPID_CLICKS; press++) await b.page.keyboard.press('Enter')
  for (let press = 0; press < RAPID_CLICKS; press++) await b.page.keyboard.press('Space')
  await wait(SETTLE_MS)
  check('Ruvio switch: Enter and Space pressed five times each send exactly 1 request', watch.count() === 1, `${watch.count()}`)
}

export async function switchGoesBackWhenRefused(b: Browse, standin: StandIn, watch: Watch): Promise<void> {
  await openSwitch(b, standin)
  watch.clear()
  standin.behaviour.refuseWith = REFUSAL
  standin.behaviour.delayMs = SLOW_MS
  await b.page.click(SWITCH)
  await wait(SEEN_BUSY_AFTER_MS)
  check('Ruvio switch: it shows the new position while the request runs', (await switchView(b)).on)
  await b.until((selector) => document.querySelector(selector)?.parentElement?.querySelector('.what .aline.bad') !== null, { timeout: SHORT_WAIT_MS }, SWITCH)
  const failed = await switchView(b)
  check('Ruvio switch: a refusal puts it back to off, shows the reason next to it and frees it', failed.found && !failed.on && !failed.disabled && failed.ariaBusy === 'false' && failed.words === REFUSAL, JSON.stringify(failed))
  await b.shot('actions-ruvio-failed.png')
  standin.behaviour.refuseWith = null
  await b.page.click(SWITCH)
  await wait(SETTLE_MS)
  check('Ruvio switch: after a refusal a second try goes through', watch.count() === 2 && (await switchView(b)).on, `${watch.count()}`)
}

export async function successLineGoesAway(b: Browse, standin: StandIn): Promise<void> {
  await openControl(b, standin, controlNamed('Roll back'))
  await burst(b, 'Roll back to 0.3.0', 1)
  await b.until(() => document.querySelector('.top .aline')?.textContent?.trim() === 'Rolled back', { timeout: SHORT_WAIT_MS })
  const shownAt = Date.now()
  await b.until(() => (document.querySelector('.top .aline')?.textContent?.trim() ?? '') === '', { timeout: SHORT_WAIT_MS })
  const shownFor = Date.now() - shownAt
  check(`the "Rolled back" line goes away by itself after about 2 s (${shownFor} ms)`, shownFor >= SUCCESS_LINE_MIN_MS - SEEN_BUSY_AFTER_MS && shownFor <= SUCCESS_LINE_MAX_MS)
}

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

export async function onAPhone(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  await fresh(b, standin, VM_PAGE)
  await waitForButton(b, 'Install chat')
  standin.behaviour.delayMs = SLOW_MS
  await burst(b, 'Install chat', 1)
  await wait(SEEN_BUSY_AFTER_MS)
  check('phone: no sideways scrolling while Install chat is busy', await noSideScroll(b))
  await b.shot('actions-install-busy-phone.png')
  await wait(SETTLE_MS)
  await fresh(b, standin, SETTINGS)
  standin.behaviour.refuseWith = REFUSAL
  await waitForButton(b, 'Pin')
  await burst(b, 'Pin', 1)
  await b.until(() => document.querySelector('.aline.bad') !== null, { timeout: SHORT_WAIT_MS })
  check('phone: the failed Pin line fits the screen', await noSideScroll(b))
  await b.shot('actions-pin-failed-phone.png')
  await openSwitch(b, standin)
  standin.behaviour.delayMs = SLOW_MS
  await b.page.click(SWITCH)
  await wait(SEEN_BUSY_AFTER_MS)
  check('phone: no sideways scrolling while the Ruvio switch saves', await noSideScroll(b))
  await b.shot('actions-ruvio-saving-phone.png')
  await b.page.setViewport(DESKTOP)
}
