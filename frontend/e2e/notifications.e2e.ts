// Long actions and notifications in a real browser against a stand-in parent (e2e/notifications/data.ts): the bell and its count, the Notifications page with 63 stand-in rows
// (paging, unread highlight, mark read, mark all read, Local | UTC, a click to the VM, hostile text as text), and the job lines on the VM rows and the VM page (a running
// delete with its step, a timed out one, a lost contact one, a failed stop with Retry, a second delete refused with 409 already_deleting). Pictures at desktop and phone width.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/notifications.e2e.ts   (needs a built panel and Google Chrome)
import puppeteer from 'puppeteer-core'
import { ALREADY_DELETING, BACKUP_STEP, MACHINE, NOTIFICATION_COUNT, PAGE_SIZE_DEFAULT, UNREAD_COUNT, VM_LOST_CONTACT, VM_RUNNING_DELETE, VM_STOP_FAILED, VM_TIMED_OUT, makeNotifications, notificationRoutes, standInMachines } from './notifications/data.ts'
import { startFakeParent } from './machine/fake-parent.ts'
import { SHORT_WAIT_MS, expectNoSideScroll } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 400, height: 844 } }
const ROWS = '[data-testid=notifications-list] > li'
const JOBS = '[data-testid=job-line]'

const count = (b: Browse, selector: string) => b.run((one) => document.querySelectorAll(one).length, selector)
const bellText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-testid=bell-count]')?.innerText ?? '')
const showing = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-testid=pagination-showing]')?.innerText ?? '')
const goToPage = (b: Browse, page: number) => b.run((label) => document.querySelector<HTMLButtonElement>(`[data-testid=pagination] button[aria-label="${label}"]`)?.click(), `Page ${page}`)
const jobText = (b: Browse, vm: string) => b.run((id) => [...document.querySelectorAll<HTMLElement>(`tr:has(a[href*="vm=${id}"]) [data-testid=job-line], li:has(a[href*="vm=${id}"]) [data-testid=job-line]`)].map((line) => line.innerText).join('|'), vm)

async function open(b: Browse, base: string, hash: string, ready: string) {
  await b.page.goto(`${base}/#${hash}`, { waitUntil: 'networkidle0' })
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.until((selector) => document.querySelector(selector) !== null, { timeout: SHORT_WAIT_MS }, ready)
}

async function jobLines(b: Browse, base: string) {
  await open(b, base, '/vms', JOBS)
  check('the bell shows the unread count', (await bellText(b)) === String(UNREAD_COUNT), await bellText(b))
  check('four VMs show a job line', (await count(b, JOBS)) === 4, String(await count(b, JOBS)))
  const running = await jobText(b, VM_RUNNING_DELETE)
  check('a running delete shows its current step', running.includes(BACKUP_STEP), running)
  check('and has no Retry', !running.includes('Retry'))
  const timedOut = await jobText(b, VM_TIMED_OUT)
  check('a timed out delete says it took too long and to check the machine', timedOut.includes('took too long') && timedOut.includes('Check the machine'), timedOut)
  const lost = await jobText(b, VM_LOST_CONTACT)
  check('a lost contact delete says the machine stopped answering and the last step', lost.includes('stopped answering') && lost.includes('last step was Deleting'), lost)
  check('Retry is offered for the timed out delete, the lost contact delete and the failed stop', (await jobText(b, VM_TIMED_OUT)).includes('Retry') && lost.includes('Retry') && (await jobText(b, VM_STOP_FAILED)).includes('Retry'))
  await b.shot('notifications-vm-rows-desktop.png')
  await b.page.setViewport(SIZES.phone)
  await expectNoSideScroll(b, 'VM rows on a phone')
  await b.shot('notifications-vm-rows-phone.png', true)
  await b.page.setViewport(SIZES.desktop)
}

async function vmPage(b: Browse, base: string) {
  await open(b, base, `/machines/details?id=${MACHINE}&vm=${VM_RUNNING_DELETE}`, JOBS)
  const text = await b.run(() => document.querySelector<HTMLElement>('[data-testid=job-line]')?.innerText ?? '')
  check('the VM page shows the running delete step', text.includes(BACKUP_STEP), text)
  await b.shot('notifications-vm-page-desktop.png')
  await b.page.setViewport(SIZES.phone)
  await expectNoSideScroll(b, 'VM page on a phone')
  await b.shot('notifications-vm-page-phone.png')
  await b.page.setViewport(SIZES.desktop)
}

async function retryDelete(b: Browse, base: string, deletes: string[]) {
  await open(b, base, '/vms', JOBS)
  const clicked = await b.run((id) => {
    const row = document.querySelector<HTMLElement>(`tr:has(a[href*="vm=${id}"]), li:has(a[href*="vm=${id}"])`)
    const retry = [...(row?.querySelectorAll('button') ?? [])].find((button) => button.textContent?.trim() === 'Retry')
    retry?.click()
    return retry !== undefined
  }, VM_TIMED_OUT)
  check('Retry on the timed out delete opens the usual confirm window', clicked)
  await b.until(() => document.querySelector('dialog[open]') !== null, { timeout: SHORT_WAIT_MS })
  await b.click('Delete VM')
  await b.until((wanted) => document.querySelector<HTMLElement>('dialog[open]')?.innerText.includes(wanted), { timeout: SHORT_WAIT_MS }, ALREADY_DELETING)
  const dialog = await b.dialogText()
  check('a second delete answered 409 already_deleting shows the message once', dialog.split(ALREADY_DELETING).length === 2, dialog)
  check('exactly one delete was sent, and no error toasts pile up', deletes.length === 1 && (await count(b, '[role=alert]')) <= 2, String(deletes.length))
}

async function list(b: Browse, base: string, state: ReturnType<typeof makeNotifications>) {
  await open(b, base, '/notifications', ROWS)
  check('the list opens on page 1 with 25 rows', (await count(b, ROWS)) === PAGE_SIZE_DEFAULT, String(await count(b, ROWS)))
  check('it says which rows of how many', (await showing(b)) === `Showing 1 to 25 of ${NOTIFICATION_COUNT}`, await showing(b))
  check('the unread ones are highlighted', (await count(b, `${ROWS}.unread`)) === UNREAD_COUNT, String(await count(b, `${ROWS}.unread`)))
  const hostile = await b.run(() => ({ xss: Reflect.get(window, '__xss') ?? 0, images: document.querySelectorAll('[data-testid=notifications-list] img').length, text: document.body.innerText.includes('<img src=x') }))
  check('hostile text in a title stays text', hostile.xss === 0 && hostile.images === 0 && hostile.text, JSON.stringify(hostile))
  check('an unknown kind is shown as a neutral Notice', await b.run(() => document.querySelector('li[data-kind=other] .tag')?.textContent?.trim() === 'Notice'))
  await b.shot('notifications-list-desktop.png')
  await goToPage(b, 3)
  await b.until((wanted) => document.querySelector<HTMLElement>('[data-testid=pagination-showing]')?.innerText === wanted, { timeout: SHORT_WAIT_MS }, `Showing 51 to ${NOTIFICATION_COUNT} of ${NOTIFICATION_COUNT}`)
  check('page 3 shows the last 13 rows', (await count(b, ROWS)) === NOTIFICATION_COUNT - 2 * PAGE_SIZE_DEFAULT, String(await count(b, ROWS)))
  await b.shot('notifications-list-page3-desktop.png')
  await goToPage(b, 1)
  await b.until(() => document.querySelectorAll('[data-testid=notifications-list] > li').length === 25, { timeout: SHORT_WAIT_MS })
  await localAndUtc(b)
  await b.page.setViewport(SIZES.phone)
  await expectNoSideScroll(b, 'notifications on a phone')
  await b.shot('notifications-list-phone.png')
  await b.page.setViewport(SIZES.desktop)
  await readMarks(b, state)
}

async function localAndUtc(b: Browse) {
  const local = await b.run(() => document.querySelector('[data-testid=notifications-list] time')?.textContent ?? '')
  await b.click('UTC')
  const utc = await b.run(() => document.querySelector('[data-testid=notifications-list] time')?.textContent ?? '')
  check('the UTC switch shows times in UTC', utc.endsWith('UTC'), `${local} -> ${utc}`)
  await b.click('Local')
}

async function readMarks(b: Browse, state: ReturnType<typeof makeNotifications>) {
  await b.run(() => document.querySelector<HTMLButtonElement>(`${'[data-testid=notifications-list] > li.unread'} [data-testid=mark-read]`)?.click())
  await b.until((wanted) => document.querySelector<HTMLElement>('[data-testid=bell-count]')?.innerText === wanted, { timeout: SHORT_WAIT_MS }, String(UNREAD_COUNT - 1))
  check('Mark read on one row sends its id and lowers the bell', JSON.stringify(state.reads[0]) === JSON.stringify({ ids: [NOTIFICATION_COUNT] }), JSON.stringify(state.reads))
  await b.click('Mark all read')
  await b.until(() => document.querySelector('[data-testid=bell-count]') === null, { timeout: SHORT_WAIT_MS })
  check('Mark all read sends all:true and clears the bell and the highlight', JSON.stringify(state.reads[1]) === JSON.stringify({ all: true }) && (await count(b, `${ROWS}.unread`)) === 0, JSON.stringify(state.reads))
  await b.shot('notifications-list-read-desktop.png')
  await b.run(() => document.querySelector<HTMLAnchorElement>('[data-testid=open-target]')?.click())
  await b.until(() => location.hash.includes('vm='), { timeout: SHORT_WAIT_MS })
  check('Open goes to the VM the notification names', await b.run(() => location.hash.includes(`id=${'rtx-pc'}`)), await b.run(() => location.hash))
}

const state = makeNotifications()
const parent = startFakeParent({ chatsBuilt: 0, dist: panelDist, machines: standInMachines(), routes: notificationRoutes(state) })
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const b = browse(page)
  await jobLines(b, parent.base)
  await vmPage(b, parent.base)
  await retryDelete(b, parent.base, state.deletes)
  await list(b, parent.base, state)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.stop()
}
finish()
