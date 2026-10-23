// The GPU memory limit ("shared partition") in a real browser against a stand-in parent that applies the booking rule: the choice and its reasons in the Create VM window, the number field and its checks,
// what is sent (one request for rapid clicks, the old bodies for the other choices), a server refusal inside the window, the booking on the Live tab, the "GPU 4 GB" chip in the lists, the VM page row, and why a VM stopped over its limit.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/gpu-limit.e2e.ts   (needs a built panel, Google Chrome, `bun install` in frontend/)
import puppeteer from 'puppeteer-core'
import { machineChangeResets, numberField, oneRequestForRapidClicks, openCreate, optionsPerMachine, sendsTheOldBodies, serverRefusalStaysInTheModal } from './gpu/limit-create-steps.ts'
import { bookingOnTheLiveTab, chipsInTheLists, overLimitReason, vmPageRow } from './gpu/limit-show-steps.ts'
import { SHARE_PC, startLimitStandIn } from './gpu/limit-stand-in.ts'
import { check, finish } from './support/check.ts'
import { GPU, choose } from './support/createVm.ts'
import { chromePath, panelDist } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'

const SIZES = { desktop: { width: 1280, height: 1000 }, phone: { width: 400, height: 900 } }
const BOOKED_AFTER_CREATE = 14
const SHORT_WAIT_MS = 10000

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

async function onAPhone(b: Browse, base: string): Promise<void> {
  await b.page.setViewport(SIZES.phone)
  await openCreate(b, base, SHARE_PC)
  await choose(b, GPU, 'shared')
  await b.page.waitForSelector('#vm-create-gpu-memory')
  check('Create VM with the Shared partition number has no sideways scrolling at 400 px', await noSideScroll(b))
  await b.shot('gpu-limit-select-shared-phone.png', true)
  await b.page.goto(`${base}/#/vms`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr', { timeout: SHORT_WAIT_MS })
  check('All VMs with the chip has no sideways scrolling at 400 px', await noSideScroll(b))
  await b.shot('gpu-limit-all-vms-phone.png', true)
  await b.page.goto(`${base}/#/machines/details?id=${SHARE_PC}`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('[data-testid=gpu-booking]', { timeout: SHORT_WAIT_MS })
  check('the Live tab with the booking line has no sideways scrolling at 400 px', await noSideScroll(b))
  await b.shot('gpu-limit-live-booking-phone.png', true)
  await b.page.goto(`${base}/#/machines/details?id=${SHARE_PC}&vm=overran`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('section.why', { timeout: SHORT_WAIT_MS })
  check('the stopped VM page has no sideways scrolling at 400 px', await noSideScroll(b))
  await b.shot('gpu-limit-stopped-vm-phone.png', true)
  await b.page.setViewport(SIZES.desktop)
}

const world = startLimitStandIn(panelDist)
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (400|409)/.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { window.violation = event.violatedDirective }))
  const b = browse(page)
  await optionsPerMachine(b, world.base)
  await numberField(b, world.base)
  await machineChangeResets(b, world.base)
  await bookingOnTheLiveTab(b, world.base)
  await chipsInTheLists(b, world.base)
  await vmPageRow(b, world.base)
  await overLimitReason(b, world.base)
  await serverRefusalStaysInTheModal(b, world)
  await sendsTheOldBodies(b, world)
  await oneRequestForRapidClicks(b, world)
  await bookingOnTheLiveTab(b, world.base, BOOKED_AFTER_CREATE)
  await onAPhone(b, world.base)
  check('no script errors and no policy violations', errors.length === 0 && (await b.run(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  world.stop()
}
finish()
