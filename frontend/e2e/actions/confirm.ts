// Every delete or remove button opens the one shared red confirm dialog first, and nothing is sent until the red button is pressed.
// The dialog has a title, a sentence naming what goes, a red verb button and Cancel, and the focus starts on Cancel.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { burst, fresh, openTable, waitForButton } from './guard.ts'
import type { StandIn } from './standin.ts'

const VMS_TAB = '#/machines/details?id=studio&tab=vms'
const VM_DANGER_PAGE = '#/machines/details?id=studio&vm=vm1'
const MACHINES = '#/machines'
const MACHINE_PAGE = '#/machines/details?id=studio'
const SHORT_WAIT_MS = 8000
const SETTLE_MS = 300

interface Entry {
  name: string
  hash: string
  /** Gets the page ready and presses the button that must open the dialog. */
  press: (b: Browse) => Promise<void>
  title: string
  verb: string
  /** A word the sentence must contain: the name of what goes. */
  names: string
}

const pressLabelled = (b: Browse, label: string) => b.page.click(`button[aria-label="${label}"]`)

async function pressCardDelete(b: Browse): Promise<void> {
  await b.click('Cards')
  await b.page.waitForSelector('.card')
  await waitForButton(b, 'Delete')
  await burst(b, 'Delete', 1)
}

async function pressTableDelete(b: Browse): Promise<void> {
  await openTable(b)
  await waitForButton(b, 'Delete')
  await burst(b, 'Delete', 1)
}

async function pressDangerTab(b: Browse): Promise<void> {
  await b.run(() => [...document.querySelectorAll<HTMLElement>('[role=tab]')].find((tab) => tab.textContent?.trim() === 'Danger')?.click())
  await b.click('Delete instance')
}

const ENTRIES: Entry[] = [
  { name: 'Machines list: Remove', hash: MACHINES, press: (b) => pressLabelled(b, 'Remove studio'), title: 'Remove this machine?', verb: 'Remove machine', names: 'studio' },
  { name: 'Machine page: Remove', hash: MACHINE_PAGE, press: (b) => pressLabelled(b, 'Remove studio'), title: 'Remove this machine?', verb: 'Remove machine', names: 'studio' },
  { name: 'VMs table: Delete', hash: VMS_TAB, press: pressTableDelete, title: 'Delete this VM?', verb: 'Delete VM', names: 'vm1' },
  { name: 'VMs cards: Delete', hash: VMS_TAB, press: pressCardDelete, title: 'Delete this VM?', verb: 'Delete VM', names: 'vm1' },
  { name: 'VM page: Delete instance', hash: VM_DANGER_PAGE, press: pressDangerTab, title: 'Delete this VM?', verb: 'Delete VM', names: 'vm1' },
]

/** Counts every request that could change something: anything that is not a plain read. */
export function watchWrites(page: Page) {
  let count = 0
  page.on('request', (request) => {
    if (request.method() !== 'GET') count += 1
  })
  return { count: () => count, clear: () => { count = 0 } }
}

type Writes = ReturnType<typeof watchWrites>

interface DialogView {
  title: string
  sentence: string
  redLabel: string
  cancelFocused: boolean
}

const dialogView = (b: Browse): Promise<DialogView> =>
  b.run(() => {
    const dialog = document.querySelector('dialog[open]')
    const cancel = [...(dialog?.querySelectorAll('button') ?? [])].find((button) => button.textContent?.trim() === 'Cancel')
    return {
      title: dialog?.querySelector('h3')?.textContent?.trim() ?? '',
      sentence: dialog?.querySelector('p')?.textContent?.trim() ?? '',
      redLabel: dialog?.querySelector('button.btn.danger')?.textContent?.trim() ?? '',
      cancelFocused: cancel !== undefined && document.activeElement === cancel,
    }
  })

async function opensTheSharedDialog(b: Browse, standin: StandIn, writes: Writes, entry: Entry): Promise<void> {
  await fresh(b, standin, entry.hash)
  await b.page.waitForSelector('main')
  writes.clear()
  await entry.press(b)
  await b.page.waitForSelector('dialog[open]', { timeout: SHORT_WAIT_MS })
  await b.until(() => document.activeElement?.textContent?.trim() === 'Cancel', { timeout: SHORT_WAIT_MS })
  const view = await dialogView(b)
  check(`${entry.name}: opens the shared dialog "${entry.title}" with a red "${entry.verb}" and the focus on Cancel`, view.title === entry.title && view.redLabel === entry.verb && view.cancelFocused, JSON.stringify(view))
  check(`${entry.name}: the sentence names ${entry.names}`, view.sentence.includes(entry.names), view.sentence)
  await wait(SETTLE_MS)
  check(`${entry.name}: nothing is sent before the red button is pressed`, writes.count() === 0 && standin.calls.length === 0, `${writes.count()} ${standin.calls.join()}`)
  if (entry.name === 'VMs table: Delete') await b.shot('confirm-dialog-delete-vm.png')
  await b.click('Cancel')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  check(`${entry.name}: Cancel closes it and still nothing is sent`, writes.count() === 0 && standin.calls.length === 0)
}

export async function everyDestructiveButtonAsksFirst(b: Browse, standin: StandIn, writes: Writes): Promise<void> {
  for (const entry of ENTRIES) await opensTheSharedDialog(b, standin, writes, entry)
}
