// The CPU settings of a new VM, as in Proxmox's Processors window, in a real browser against a stand-in parent that applies the parent's rules: Sockets, Cores, Type and Total cores,
// the Model and Vendor list and its keys, the extra CPU flags, a container's CPU limit, what a machine cannot set and why, what is sent (and the old bodies when nothing is touched),
// a reset when the machine changes, the ↺ Reset, a refusal inside the window, and a phone.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/cpu-options.e2e.ts   (needs a built panel, Google Chrome, `bun install` in frontend/)
import puppeteer from 'puppeteer-core'
import { containerLimit, flagsTable, machineChangeResets, openCreate, resetButton, rowsAndTypeList, sendsTheChoices, sendsTheOldBodies, serverRefusalStaysInTheModal, socketsAndCores, whatMachinesCannotSet } from './cpu/steps.ts'
import { CPU_PC, startCpuStandIn } from './cpu/stand-in.ts'
import { check, finish } from './support/check.ts'
import { chromePath, panelDist } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'

const SIZES = { desktop: { width: 1280, height: 1000 }, phone: { width: 400, height: 900 } }

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

async function onAPhone(b: Browse, base: string): Promise<void> {
  await b.page.setViewport(SIZES.phone)
  await openCreate(b, base, CPU_PC)
  check('Create VM with the CPU rows and the flags has no sideways scrolling at 400 px', await noSideScroll(b))
  await b.page.evaluate(() => document.querySelector('dialog[open] [data-cpu-flags]')?.scrollIntoView())
  check('the flags stack on a phone and stay inside the window', await b.run(() => {
    const dialog = document.querySelector('dialog[open]')?.getBoundingClientRect()
    const table = document.querySelector('dialog[open] [data-cpu-flags] table')?.getBoundingClientRect()
    return dialog !== undefined && table !== undefined && table.left >= dialog.left && table.right <= dialog.right
  }))
  await b.shot('cpu-flags-phone.png')
  await b.page.keyboard.press('Escape')
  await b.page.setViewport(SIZES.desktop)
}

const world = startCpuStandIn(panelDist)
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
  await rowsAndTypeList(b, world.base)
  await socketsAndCores(b, world.base)
  await flagsTable(b, world.base)
  await whatMachinesCannotSet(b, world.base)
  await machineChangeResets(b, world.base)
  await resetButton(b, world.base)
  await serverRefusalStaysInTheModal(b, world)
  await sendsTheChoices(b, world)
  await containerLimit(b, world)
  await sendsTheOldBodies(b, world)
  await onAPhone(b, world.base)
  check('no script errors and no policy violations', errors.length === 0 && (await b.run(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  world.stop()
}
finish()
