// End-to-end test of the VMs pages in a real browser against a real Root: the VMs link in the sidebar, All VMs (the table, the Machine filter kept in the address, empty states),
// the Create VM window (who can be picked and why not, the containers-only machine, the refusal, a VM made on a simulated helper), the machine page's own button opening the same window, and a phone.
// Needs: the Root build (`swift build` in control-plane/arm64), the macOS helper build (`swift build` in agent/macos), a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/.
// Run: bun e2e/vms.e2e.ts
import { readFileSync } from 'node:fs'
import puppeteer from 'puppeteer-core'
import { ADMIN, createAdmin } from './support/admin.ts'
import { check, finish } from './support/check.ts'
import { chromePath } from './support/paths.ts'
import { browse, type Browse } from './support/page.ts'
import { resendHeartbeats, seed, startAgent, startWorld, stopWorld, type World } from './panel/world.ts'
import { closeWithEscape, kindsOnAMachine, noMachinesYet, openCreate, openingAndClosing, preselectedAndValidated, refusedThenMade, thenInAllVms, theMachinePageButton, whoCanBePicked } from './vms/create.ts'
import { addExtraMachines } from './vms/fleet.ts'
import { emptyStates, filtering, fullTable, openAllVms, openingARow } from './vms/list.ts'
import { pendingScenario } from './vms/pending.ts'
import { vmsIsOneLink, vmsLinkOnItsPages } from './vms/sidebar.ts'

const DESKTOP = { width: 1280, height: 800 }
const PHONE = { width: 400, height: 844 }
const SHORT_WAIT_MS = 10000
const SETUP_TOKEN_LINE = /^ROOT_SETUP_TOKEN=(.+)$/m

async function makeAdminAndSignIn(b: Browse, world: World): Promise<void> {
  const token = readFileSync(world.root.envFile, 'utf8').match(SETUP_TOKEN_LINE)?.[1]?.trim()
  if (!token) throw new Error('the Root did not write a setup token into its env file')
  await createAdmin(world.root.base, token)
  await b.page.goto(world.root.base, { waitUntil: 'networkidle0' })
  await b.page.type('input[name=username]', ADMIN.username)
  await b.page.type('input[name=password]', ADMIN.password)
  await b.click('Sign in')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Overview', { timeout: SHORT_WAIT_MS })
}

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
const fitsTheScreen = (b: Browse) => b.run(() => { const box = document.querySelector('dialog[open]')?.getBoundingClientRect(); return box !== undefined && box.left >= 0 && box.right <= window.innerWidth && box.bottom <= window.innerHeight })

async function onAPhone(b: Browse, world: World): Promise<void> {
  await resendHeartbeats(world)
  await b.page.setViewport(PHONE)
  await openAllVms(b)
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  check('All VMs has no sideways scrolling on a phone', await noSideScroll(b))
  check('on a phone every cell says what it is', await b.run(() => [...document.querySelectorAll('table[aria-label="VMs"] tbody tr:first-child td')].every((cell) => cell.getAttribute('data-label'))))
  await b.shot('vms-all-phone.png', true)
  await b.page.select('#vm-machine', 'mac-mini')
  await b.until(() => document.querySelectorAll('table[aria-label="VMs"] tbody tr').length === 1, { timeout: SHORT_WAIT_MS })
  await b.shot('vms-filtered-phone.png', true)
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector('#vm-create-name')
  check('the Create VM window has no sideways scrolling on a phone and fits the screen', (await noSideScroll(b)) && (await fitsTheScreen(b)))
  await b.shot('vms-create-phone.png')
  await closeWithEscape(b)
  await openCreate(b)
  await b.page.waitForSelector('#vm-create-machine')
  await b.shot('vms-create-offline-phone.png')
  check('on a phone the window scrolls inside itself when the form is taller than the screen', await b.run(() => {
    const dialog = document.querySelector<HTMLElement>('dialog[open]')
    return dialog !== null && getComputedStyle(dialog).overflowY === 'auto'
  }))
  await closeWithEscape(b)
  await b.page.setViewport(DESKTOP)
}

const world = await startWorld()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
let helper: Awaited<ReturnType<typeof startAgent>> | undefined
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|502)/.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { window.violation = event.violatedDirective }))
  const b = browse(page)

  await makeAdminAndSignIn(b, world)
  await emptyStates(b)
  await noMachinesYet(b)

  const session = await seed(world)
  await addExtraMachines(world, session)
  await page.reload({ waitUntil: 'networkidle0' })
  await vmsIsOneLink(b)
  await vmsLinkOnItsPages(b)
  await fullTable(b)
  await filtering(b)
  await openingARow(b)

  await resendHeartbeats(world)
  await whoCanBePicked(b)
  await kindsOnAMachine(b)
  await preselectedAndValidated(b)
  await openingAndClosing(b)
  helper = await startAgent(world)
  await refusedThenMade(b)
  await thenInAllVms(b)
  await theMachinePageButton(b)
  await pendingScenario(b, world)
  await onAPhone(b, world)

  check('no script errors and no policy violations', errors.length === 0 && (await b.run(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  helper?.kill()
  await browser.close()
  stopWorld(world)
}
finish()
