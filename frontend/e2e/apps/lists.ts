// The app chip next to a VM's status in the VM lists (the machine page's Table and Cards, and All VMs) in a real browser against the stand-in Root:
// a VM made with OpenClaw shows "Installing OpenClaw…" with a spinner, then "OpenClaw ready", and a failed install shows a red chip with the message as its hover text and, on a phone, as a visible line.
import { fresh, openTable } from '../actions/guard.ts'
import type { StandIn } from '../actions/standin.ts'
import { check } from '../support/check.ts'
import { FRAMEWORK, NAME, choose } from '../support/createVm.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { DESKTOP, MACHINE_VMS, openCreateWindow, PHONE, SHORT_WAIT_MS } from './catalog.ts'

const ALL_VMS = '#/vms'
const CREATED_VM = 'vm5'
const FAILED_VM = 'vm2'
const FAILURE = 'Could not install hermes: the VM has no network.'
const SETTLE_MS = 400

interface ChipView {
  text: string
  title: string | null
  spinner: boolean
  tone: string
  detail: string
}

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

/** The chip in the row or card of this VM, or null when it has none. */
const chipOf = (b: Browse, vm: string): Promise<ChipView | null> =>
  b.run((wanted) => {
    const chip = [...document.querySelectorAll<HTMLElement>('[data-app-chip]')].find((entry) => entry.closest('tr, .card')?.textContent?.includes(wanted))
    if (!chip) return null
    const detail = chip.parentElement?.querySelector<HTMLElement>('.detail')
    return {
      text: chip.textContent?.replace(/\s+/g, ' ').trim() ?? '',
      title: chip.getAttribute('title'),
      spinner: chip.querySelector('.btn-spin') !== null,
      tone: chip.getAttribute('data-app-chip') ?? '',
      detail: detail && detail.getClientRects().length > 0 ? detail.innerText.trim() : '',
    }
  }, vm)

const chipShows = (b: Browse, vm: string, text: string) =>
  b.until((wanted, expected) => [...document.querySelectorAll<HTMLElement>('[data-app-chip]')].some((chip) => chip.closest('tr, .card')?.textContent?.includes(wanted) && chip.textContent?.replace(/\s+/g, ' ').trim() === expected), { timeout: SHORT_WAIT_MS }, vm, text)

async function reload(b: Browse): Promise<void> {
  await b.page.reload({ waitUntil: 'networkidle0' })
}

/** Makes a VM with OpenClaw through the Create VM window, with one click, and waits for the window to close. */
async function createClawVm(b: Browse): Promise<void> {
  await openCreateWindow(b)
  await b.type(NAME, 'claw-box')
  await choose(b, FRAMEWORK, 'openclaw')
  await b.click('Create VM')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
}

/** A new VM shows Installing OpenClaw… in the Table, the Cards and All VMs; when the install ends it shows OpenClaw ready. */
export async function chipFollowsTheInstall(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  await createClawVm(b)
  await openTable(b)
  await chipShows(b, CREATED_VM, 'Installing OpenClaw…')
  const installing = await chipOf(b, CREATED_VM)
  check('Table: the new VM shows Installing OpenClaw… with the panel spinner', installing?.tone === 'busy' && installing.spinner, JSON.stringify(installing))
  await b.shot('apps-row-installing-desktop.png')
  await b.click('Cards')
  await chipShows(b, CREATED_VM, 'Installing OpenClaw…')
  check('Cards: the same chip', (await chipOf(b, CREATED_VM))?.spinner === true)
  await b.go(ALL_VMS)
  await chipShows(b, CREATED_VM, 'Installing OpenClaw…')
  check('All VMs: the same chip', (await chipOf(b, CREATED_VM))?.tone === 'busy')
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS)
  check('phone 400px: All VMs with the chip does not scroll sideways', await noSideScroll(b))
  await b.shot('apps-row-installing-phone.png')
  await b.page.setViewport(DESKTOP)
  standin.apps.finish(CREATED_VM)
  await reload(b)
  await chipShows(b, CREATED_VM, 'OpenClaw ready')
  const ready = await chipOf(b, CREATED_VM)
  check('after the install ends the chip says OpenClaw ready, in green, without a spinner', ready?.tone === 'ok' && !ready.spinner, JSON.stringify(ready))
  await b.shot('apps-row-ready-desktop.png')
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS)
  await b.shot('apps-row-ready-phone.png')
  await b.page.setViewport(DESKTOP)
}

/** A failed install shows a red chip with the message as hover text; on a phone the message is a visible line. */
export async function failedChipShowsTheMessage(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  standin.apps.failure = FAILURE
  standin.apps.begin(FAILED_VM, 'hermes')
  standin.apps.finish(FAILED_VM)
  await reload(b)
  await openTable(b)
  await chipShows(b, FAILED_VM, 'Hermes install failed')
  const table = await chipOf(b, FAILED_VM)
  check('Table: the failed install shows a red chip with the message as its hover text', table?.tone === 'bad' && table.title === FAILURE, JSON.stringify(table))
  check('on a desktop the message is not repeated as a line under the chip', table?.detail === '', JSON.stringify(table))
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS)
  const phone = await chipOf(b, FAILED_VM)
  check('phone 400px: the message is a visible line under the chip', phone?.detail === FAILURE, JSON.stringify(phone))
  check('phone 400px: the Table with the failed chip does not scroll sideways', await noSideScroll(b))
  await b.click('Cards')
  await chipShows(b, FAILED_VM, 'Hermes install failed')
  check('phone 400px: Cards show the message and do not scroll sideways', (await chipOf(b, FAILED_VM))?.detail === FAILURE && (await noSideScroll(b)))
  await b.page.setViewport(DESKTOP)
}

/** A VM with no app has no chip anywhere. */
export async function noChipWithoutAnApp(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  await openTable(b)
  check('VMs without an app have no chip', (await b.page.$$('[data-app-chip]')).length === 0)
}
