// Paging in a real browser with big data: the process list (800 programs) and the Security log (5,000 events) must draw one page of rows, not all of them.
// Checks: one page of rows in the page, page 2 shows the right rows and the "Showing" text, the 2 second refresh of the process list keeps the same row
// elements and builds no more of them, the page size choice changes the page. The DOM node counts are printed so a change in cost can be seen.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/pagination.e2e.ts   (needs a built panel and Google Chrome)
import puppeteer, { type Page } from 'puppeteer-core'
import { BIG_LOG_ROWS, securityRoutes, type SecurityStandIn } from './security/api.ts'
import { securityMachines } from './security/data.ts'
import { startFakeParent } from './machine/fake-parent.ts'
import { startStandIn } from './monitor/stand-in.ts'
import { SHORT_WAIT_MS, openMachine } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { wait } from './support/net.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const PROCESS_COUNT = 800
const PROCESS_PAGE = 25
const SECOND_PAGE_FIRST_PROCESS = 'worker-26'
const REFRESH_WAIT_MS = 7000
const LOG_ROWS = '[data-testid=security-log] tbody tr'
const PROCESS_ROWS = 'dialog[open] .procs tbody tr'
const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 400, height: 844 } }

const nodeCount = (b: Browse) => b.run(() => document.querySelectorAll('*').length)
const rowCount = (b: Browse, selector: string) => b.run((one) => document.querySelectorAll(one).length, selector)
const showing = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-testid=pagination-showing]')?.innerText ?? '')
const goToPage = (b: Browse, page: number) => b.run((label) => document.querySelector<HTMLButtonElement>(`[data-testid=pagination] button[aria-label="${label}"]`)?.click(), `Page ${page}`)
const waitShowing = (b: Browse, text: string) => b.until((wanted) => document.querySelector<HTMLElement>('[data-testid=pagination-showing]')?.innerText === wanted, { timeout: SHORT_WAIT_MS }, text)

async function processList(page: Page, b: Browse, base: string, asked: () => number) {
  await openMachine(b, base, 'studio')
  await b.click('Top processes')
  await b.until((selector) => document.querySelectorAll(selector).length > 1, { timeout: SHORT_WAIT_MS }, PROCESS_ROWS)
  const rows = await rowCount(b, PROCESS_ROWS)
  console.log(`DOM nodes with ${PROCESS_COUNT} processes in the list: ${await nodeCount(b)} (${rows} table rows)`)
  check('the process list draws one page of rows (25), not all 800', rows === PROCESS_PAGE, String(rows))
  check('it says which rows of how many', (await showing(b)) === `Showing 1 to 25 of ${PROCESS_COUNT}`, await showing(b))
  await goToPage(b, 2)
  await waitShowing(b, `Showing 26 to 50 of ${PROCESS_COUNT}`)
  const first = await b.run((selector) => document.querySelector<HTMLElement>(`${selector} .name`)?.textContent ?? '', PROCESS_ROWS)
  check('page 2 shows the programs 26 to 50 of the busiest-first order', first === SECOND_PAGE_FIRST_PROCESS && (await rowCount(b, PROCESS_ROWS)) === PROCESS_PAGE, first)
  await b.shot('pagination-processes-desktop-light.png')

  await b.run((selector) => { const row = document.querySelector<HTMLElement>(selector); if (row) row.dataset.mark = 'kept' }, PROCESS_ROWS)
  const nodesBefore = await nodeCount(b)
  const asksBefore = asked()
  await wait(REFRESH_WAIT_MS)
  check('the list was refreshed while the check waited', asked() > asksBefore, `${asksBefore} -> ${asked()}`)
  const marked = await rowCount(b, `${PROCESS_ROWS}[data-mark=kept]`)
  const nodesAfter = await nodeCount(b)
  console.log(`DOM nodes before and after a refresh: ${nodesBefore} -> ${nodesAfter}`)
  check('a refresh builds no new rows: still 25, the same row element, the same number of nodes', (await rowCount(b, PROCESS_ROWS)) === PROCESS_PAGE && marked === 1 && nodesAfter === nodesBefore)
  check('and the person stays on page 2 through the refresh', (await showing(b)) === `Showing 26 to 50 of ${PROCESS_COUNT}`)

  await b.type('dialog[open] input[type=search]', 'worker-7')
  const filtered = await showing(b)
  check('the filter works on all 800 programs, then pages (page 1 of the matches)', /^Showing 1 to 25 of \d+$/.test(filtered) && Number(filtered.split(' ').at(-1)) > PROCESS_PAGE, filtered)
  await b.type('dialog[open] input[type=search]', '')
  await page.setViewport(SIZES.phone)
  await wait(300)
  await b.shot('pagination-processes-phone-light.png')
  check('the page controls fit a phone: no sideways scroll', await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await page.setViewport(SIZES.desktop)
}

async function securityLog(b: Browse, base: string) {
  await b.page.goto(`${base}/#/security?range=30d`, { waitUntil: 'networkidle0' })
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.until((selector) => document.querySelectorAll(selector).length > 1, { timeout: SHORT_WAIT_MS }, LOG_ROWS)
  const rows = await rowCount(b, LOG_ROWS)
  console.log(`DOM nodes with ${BIG_LOG_ROWS} events in the log: ${await nodeCount(b)} (${rows} table rows)`)
  check('the Security log draws one page of rows (50) of 5,000', rows === 50 && (await showing(b)) === 'Showing 1 to 50 of 5,000', await showing(b))
  await goToPage(b, 2)
  await waitShowing(b, 'Showing 51 to 100 of 5,000')
  const addresses = await b.run((selector) => [...document.querySelectorAll(`${selector} td[data-label=Address]`)].map((cell) => cell.textContent ?? ''), LOG_ROWS)
  check('page 2 holds 50 rows and starts with the 51st newest event', addresses.length === 50 && addresses[0] === '10.50.0.1', addresses[0])
  await b.page.select('[data-testid=page-size]', '100')
  await b.until((selector) => document.querySelectorAll(selector).length === 100, { timeout: SHORT_WAIT_MS }, LOG_ROWS)
  console.log(`DOM nodes with page size 100: ${await nodeCount(b)}`)
  check('page size 100 holds 100 rows and goes back to page 1', (await showing(b)) === 'Showing 1 to 100 of 5,000', await showing(b))
  await b.page.select('[data-testid=page-size]', '50')
  await b.until((selector) => document.querySelectorAll(selector).length === 50, { timeout: SHORT_WAIT_MS }, LOG_ROWS)
  await goToPage(b, 100)
  await waitShowing(b, 'Showing 4,951 to 5,000 of 5,000')
  check('the last page is page 100 and Next is disabled there', await b.run(() => document.querySelector<HTMLButtonElement>('[data-testid=page-next]')?.disabled === true))
  await b.shot('pagination-security-big-desktop-light.png')
}

const errors: string[] = []
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const monitor = startStandIn(panelDist, PROCESS_COUNT)
const standIn: SecurityStandIn = { missing: false, big: true }
const parent = startFakeParent({ chatsBuilt: 0, dist: panelDist, machines: securityMachines(), routes: securityRoutes(standIn) })
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const b = browse(page)
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await processList(page, b, monitor.base, () => monitor.askedWithProcesses.studio?.length ?? 0)
  await securityLog(b, parent.base)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  monitor.stop()
  parent.stop()
}
finish()
