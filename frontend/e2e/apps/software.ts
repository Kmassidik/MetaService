// The Software block of a VM's page in a real browser against the stand-in Root: the state line, polling every 5 seconds only while the app installs (and not after the page closes),
// the version, the last 12 lines of the log as plain text (a hostile line stays text), and Try again sending one retry for five rapid clicks and showing a refusal next to the button.
import { burst, fresh, waitForButton } from '../actions/guard.ts'
import { INSTALLED_VERSION } from '../actions/appBook.ts'
import type { StandIn } from '../actions/standin.ts'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { DESKTOP, openConfigured, PHONE, SHORT_WAIT_MS } from './catalog.ts'

const RUNNING_VM = '#/machines/details?id=studio&vm=vm1'
const STOPPED_VM = '#/machines/details?id=studio&vm=vm2'
const PLAIN_VM = '#/machines/details?id=studio&vm=vm3'
const OTHER_PAGE = '#/vms'
const POLL_MS = 5000
const QUIET_MS = 6500
const WAIT_FOR_READY_MS = 20_000
const FAILURE = 'Could not install openclaw: the VM has no network.'
const HOSTILE = '<img src=x onerror="window.__xss=1">'
const NOT_RUNNING = 'Start the VM first.'
const LOG_LENGTH = 15
const LOG_SHOWN = 12
const RAPID_CLICKS = 5
const SLOW_MS = 700
const SETTLE_MS = 1600
const log = Array.from({ length: LOG_LENGTH - 1 }, (_, index) => `step ${index + 1}`)

/** An install in this VM that is over and failed, with a log longer than the block shows and a hostile last line. */
function failedInstall(vm: string, app: string, standin: StandIn): void {
  standin.apps.failure = FAILURE
  standin.apps.logTail = [...log, HOSTILE]
  standin.apps.installPolls = 0
  standin.apps.begin(vm, app)
}

const block = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('section[aria-label="Software"]')?.innerText.replace(/\s+/g, ' ').trim() ?? '')
const blockHas = (b: Browse, text: string) => b.until((wanted) => document.querySelector<HTMLElement>('section[aria-label="Software"]')?.innerText.includes(wanted) === true, { timeout: WAIT_FOR_READY_MS }, text)
const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
const gets = (standin: StandIn) => standin.apps.requests.filter((request) => request.startsWith('GET')).length

/** While installing the block asks every 5 seconds, then stops once the app is ready. */
export async function pollsOnlyWhileInstalling(b: Browse, standin: StandIn): Promise<void> {
  await openConfigured(b, standin, RUNNING_VM, () => {
    standin.apps.installPolls = 1
    standin.apps.begin('vm1', 'openclaw')
  })
  await blockHas(b, 'Installing… about 2 minutes')
  const first = await block(b)
  check('the block shows OpenClaw and the installing line with a spinner', first.includes('OpenClaw') && (await b.page.$('section[aria-label="Software"] .btn-spin')) !== null, first)
  check('the OpenClaw logo is drawn from the bundle', await b.run(() => { const img = document.querySelector<HTMLImageElement>('section[aria-label="Software"] img'); return img !== null && img.complete && img.naturalWidth > 0 && img.currentSrc.endsWith('.svg') }))
  check('one request on opening, none yet again', gets(standin) === 1, `${gets(standin)}`)
  await b.shot('apps-software-installing-desktop.png', true)
  await blockHas(b, 'Ready')
  const done = await block(b)
  check('after a poll it says Ready with the version', done.includes('Ready') && done.includes(`version ${INSTALLED_VERSION}`) && !done.includes('Installing'), done)
  check('it asked exactly twice by then (the opening and one poll after 5 seconds)', gets(standin) === 2, `${gets(standin)}`)
  const atReady = gets(standin)
  await wait(QUIET_MS)
  check('once ready it stops asking', gets(standin) === atReady, `${atReady} then ${gets(standin)}`)
  await b.shot('apps-software-ready-desktop.png', true)
}

/** Leaving the page while it installs stops the asking. */
export async function stopsWhenThePageCloses(b: Browse, standin: StandIn): Promise<void> {
  await openConfigured(b, standin, RUNNING_VM, () => {
    standin.apps.installPolls = 9
    standin.apps.begin('vm1', 'openclaw')
  })
  await blockHas(b, 'Installing')
  await wait(POLL_MS + SETTLE_MS / 2)
  const before = gets(standin)
  await b.go(OTHER_PAGE)
  await wait(QUIET_MS)
  check('after the page is left no more requests are made', gets(standin) <= before + 1 && before >= 2, `${before} then ${gets(standin)}`)
  const left = gets(standin)
  await wait(QUIET_MS)
  check('and none later either', gets(standin) === left, `${left} then ${gets(standin)}`)
}

/** A failed install: the message, the last 12 lines of the log as text (a hostile line stays text), and Try again sends one retry for five rapid clicks. */
export async function failedShowsMessageLogAndTryAgain(b: Browse, standin: StandIn): Promise<void> {
  await openConfigured(b, standin, RUNNING_VM, () => failedInstall('vm1', 'openclaw', standin))
  await blockHas(b, FAILURE)
  const shown = await b.run(() => document.querySelector<HTMLElement>('section[aria-label="Software"] pre')?.innerText.split('\n') ?? [])
  check(`only the last ${LOG_SHOWN} log lines are shown`, shown.length === LOG_SHOWN && shown[0] === `step ${LOG_LENGTH - LOG_SHOWN + 1}` && shown.at(-1) === HOSTILE, JSON.stringify(shown))
  check('a hostile log line stays text: no element, nothing ran', (await b.page.$('section[aria-label="Software"] pre img')) === null && (await b.run(() => window.__xss)) === undefined)
  await b.shot('apps-software-failed-desktop.png', true)
  standin.apps.requests.length = 0
  standin.apps.delayMs = SLOW_MS
  await waitForButton(b, 'Try again')
  await burst(b, 'Try again', RAPID_CLICKS)
  await wait(SETTLE_MS)
  check('five rapid clicks on Try again send exactly one retry', standin.apps.requests.filter((request) => request.startsWith('RETRY')).length === 1, standin.apps.requests.join(', '))
  await blockHas(b, 'Installing')
  check('after the retry the block says installing again and the log box is gone', (await b.page.$('section[aria-label="Software"] pre')) === null)
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS / 4)
  check('phone 400px: the block does not scroll sideways', await noSideScroll(b))
  await b.page.setViewport(DESKTOP)
}

/** The failed block on a phone, for the screenshot, and a retry on a stopped VM shows the parent's refusal next to the button. */
export async function failedOnAPhoneAndStoppedVm(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  await openConfigured(b, standin, STOPPED_VM, () => failedInstall('vm2', 'hermes', standin))
  await blockHas(b, FAILURE)
  check('phone 400px: the failed block does not scroll sideways', await noSideScroll(b))
  await b.shot('apps-software-failed-phone.png', true)
  await burst(b, 'Try again', 1)
  await b.until(() => document.querySelector('section[aria-label="Software"] .aline.bad') !== null, { timeout: SHORT_WAIT_MS })
  const refusal = await b.run(() => document.querySelector('section[aria-label="Software"] .aline.bad')?.textContent?.trim() ?? '')
  check('a retry on a stopped VM shows the refusal next to the button', refusal === NOT_RUNNING, refusal)
  check('and the button works again', !(await b.isDisabled('Try again')))
  await b.page.setViewport(DESKTOP)
}

/** A VM with no app has no Software block and never asks about one. */
export async function noBlockWithoutAnApp(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, PLAIN_VM)
  await b.page.waitForSelector('.phead h1', { timeout: SHORT_WAIT_MS })
  await wait(SETTLE_MS)
  check('a VM without an app has no Software block and makes no app request', (await b.page.$('section[aria-label="Software"]')) === null && standin.apps.requests.length === 0, standin.apps.requests.join(', '))
}
