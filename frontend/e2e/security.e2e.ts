// The Security page in a real browser against a stand-in parent with four machines (one never reports) and a stand-in Security API that can also answer 404.
// Checks: the sidebar item (present, below Sandboxes, marked on the page), the machines table with a "Not watched" row, the filters of the event log, its page numbers and page size,
// the 404 banner with every machine "Not watched", the sample-data preview and its loud banner (only when the address asks), hostile text shown as text, no sideways
// scrolling at phone width, the machine card's badge as a link, and no Security tab on the machine page. Pictures at desktop and phone width, light.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/security.e2e.ts   (needs a built panel and Google Chrome)
import puppeteer, { type Page } from 'puppeteer-core'
import { BLOCK_ROWS, FAILED_ROWS_WARNING, NEEDLE_ADDRESS, PAGE_SIZE, TOTAL_ROWS, securityRoutes, type SecurityStandIn } from './security/api.ts'
import { HEALTHY, HOSTILE_IMG, HOSTILE_NAME, MAC, OLD_HELPER, WARNING, securityMachines } from './security/data.ts'
import { startFakeParent } from './machine/fake-parent.ts'
import { SHORT_WAIT_MS, expectNoSideScroll, openMachine } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 400, height: 844 } }
const NOT_COLLECTED = 'Security data is not collected yet. Nothing here is being watched.'
const SAMPLE_BANNER = 'SAMPLE DATA. These numbers are made up to show the page. Nothing here is real.'
const SAMPLE_MACHINES = ['Mac Studio', 'Mac Mini', 'DGX Spark', 'RTX 5090 PC']
const LOG_ROWS = '[data-testid=security-log] tbody tr'

const SHOWING = '[data-testid=pagination-showing]'
const showing = (b: Browse) => b.run((selector) => document.querySelector<HTMLElement>(selector)?.innerText ?? '', SHOWING)
const goToPage = (b: Browse, page: number) => b.run((label) => document.querySelector<HTMLButtonElement>(`[data-testid=pagination] button[aria-label="${label}"]`)?.click(), `Page ${page}`)
const logCount = (b: Browse) => b.run((selector) => document.querySelectorAll(selector).length, LOG_ROWS)
const pageText = (b: Browse) => b.run(() => document.body.innerText)
const rowText = (b: Browse, id: string) => b.run((machine) => document.querySelector<HTMLElement>(`[data-testid=security-machines] tr[data-machine=${machine}]`)?.innerText ?? '', id)
const machineRowIds = (b: Browse) => b.run(() => [...document.querySelectorAll('[data-testid=security-machines] tbody tr')].map((row) => row.getAttribute('data-machine')))

async function open(b: Browse, base: string, hash: string) {
  await b.page.goto(`${base}/#${hash}`, { waitUntil: 'networkidle0' })
  // Going to the same address again does not reload the page; reload so every case starts from what the stand-in parent answers now.
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Security' && document.querySelector('[data-testid=security-machines]') !== null && !document.body.innerText.includes('Loading the log'), { timeout: SHORT_WAIT_MS })
}

async function waitLogCount(b: Browse, wanted: number) {
  await b.until((selector, count) => document.querySelectorAll(selector).length === count, { timeout: SHORT_WAIT_MS }, LOG_ROWS, wanted)
}

async function sidebar(b: Browse, base: string) {
  await open(b, base, '/security')
  const items = await b.run(() => [...document.querySelectorAll('aside nav > div')].map((group) => ({ title: group.querySelector('h3')?.textContent?.trim(), links: [...group.querySelectorAll('a')].map((link) => link.textContent?.trim()) })))
  const infrastructure = items.find((group) => group.title === 'Infrastructure')
  check('the sidebar has Security in Infrastructure, below Sandboxes', infrastructure?.links?.slice(-2).join() === 'Sandboxes,Security', JSON.stringify(infrastructure))
  check('the Security item is marked as the current page', await b.run(() => document.querySelector('aside nav a[href="#/security"]')?.getAttribute('aria-current') === 'page'))
  check('the page has its name, a one-line explanation and four time ranges', (await b.run(() => [...document.querySelectorAll('.segmented button')].map((button) => button.textContent?.trim()).join('|'))) === '24 h|7 d|30 d|90 d')
  check('the Security tab is gone from the machine page', await (async () => {
    await openMachine(b, base, HEALTHY)
    return !(await b.run(() => [...document.querySelectorAll('[role=tab]')].some((tab) => tab.textContent?.trim() === 'Security')))
  })())
}

async function machinesTable(b: Browse, base: string) {
  await open(b, base, '/security')
  check('the machines table has a row for every machine, including the one that never reported', JSON.stringify(await machineRowIds(b)) === JSON.stringify([HEALTHY, WARNING, MAC, OLD_HELPER]), JSON.stringify(await machineRowIds(b)))
  const silent = await rowText(b, OLD_HELPER)
  check('a machine that has not reported says "Not watched" and "no security data yet"', silent.toLowerCase().includes('not watched') && silent.includes('no security data yet'))
  check('and shows no zeros', !/\d/.test(silent.replace(/\s/g, '').replace(/dgx-old/g, '')), silent)
  check('the not-watched tag is in the warning colour', await b.run(() => document.querySelector('[data-testid=not-watched]')?.classList.contains('warn') === true))
  check('a watched machine has six baseline chips and its counts', (await b.run(() => document.querySelectorAll('tr[data-machine=ubuntu-box] [data-check]').length)) === 6 && (await rowText(b, HEALTHY)).includes('96,000'))
  check('password login on is a warning chip, a Mac without a ban tool is unknown', await b.run(() => document.querySelector('tr[data-machine=gpu-pc] [data-check=password_login]')?.getAttribute('data-state') === 'warning' && document.querySelector('tr[data-machine=mac-studio] [data-check=ban_tool]')?.getAttribute('data-state') === 'unknown'))
  check('the real page shows no sample banner and offers the preview link', (await b.run(() => document.querySelector('[data-testid=preview-banner]') === null && document.querySelector('[data-testid=preview-link]') !== null)))
  check('the other blocks are there: chart, blocked now, top lists, log', await b.run(() => ['Failed logins per day', 'Blocked now', 'User names the bots try', 'Addresses attacking most', 'Event log'].every((label) => document.querySelector(`section.tile[aria-label="${label}"]`) !== null)))
  check('the chart has one small chart for each machine with counts, on one scale (the tallest bar fills its chart)', await b.run(() => {
    const heights = [...document.querySelectorAll('[data-testid^=chart-] rect')].map((bar) => Number(bar.getAttribute('height')))
    return document.querySelectorAll('[data-testid^=chart-] svg').length === 2 && Math.max(...heights) === 60 && heights.every((height) => height > 0)
  }))
  check('the top lists show text and at most eight rows', await b.run(() => document.querySelectorAll('[data-testid=top-users] li').length <= 8 && document.querySelectorAll('[data-testid=top-users] li').length > 0))
  await b.shot('security-real-desktop-light.png', true)
}

async function eventLog(b: Browse, base: string) {
  await open(b, base, '/security?range=90d')
  await waitLogCount(b, PAGE_SIZE)
  check('the log shows 50 rows of 130 with page numbers', (await logCount(b)) === PAGE_SIZE && (await showing(b)) === `Showing 1 to 50 of ${TOTAL_ROWS}` && (await b.run(() => document.querySelectorAll('[data-testid=pagination] ol button').length)) === 3)
  check('the newest row is first', await b.run((selector) => {
    const times = [...document.querySelectorAll(`${selector} td[data-label=Time]`)].map((cell) => cell.getAttribute('title') ?? '')
    return times.length > 1 && times.every((time, index) => index === 0 || (times[index - 1] ?? '') >= time)
  }, LOG_ROWS))
  const firstTimes = await b.run((selector) => [...document.querySelectorAll(`${selector} td[data-label=Time]`)].map((cell) => cell.getAttribute('title')), LOG_ROWS)
  await goToPage(b, 2)
  await b.until((text) => document.querySelector<HTMLElement>('[data-testid=pagination-showing]')?.innerText === text, { timeout: SHORT_WAIT_MS }, `Showing 51 to 100 of ${TOTAL_ROWS}`)
  const secondTimes = await b.run((selector) => [...document.querySelectorAll(`${selector} td[data-label=Time]`)].map((cell) => cell.getAttribute('title') ?? ''), LOG_ROWS)
  check('page 2 shows the next 50 rows, all older than page 1', secondTimes.length === PAGE_SIZE && (secondTimes[0] ?? '') <= (firstTimes.at(-1) ?? ''))
  await b.run(() => document.querySelector<HTMLButtonElement>('[data-testid=page-next]')?.click())
  await waitLogCount(b, TOTAL_ROWS - PAGE_SIZE * 2)
  check('Next goes to the last page with the rest, and Next is then disabled', (await showing(b)) === `Showing 101 to ${TOTAL_ROWS} of ${TOTAL_ROWS}` && (await b.run(() => document.querySelector<HTMLButtonElement>('[data-testid=page-next]')?.disabled === true)))
  await goToPage(b, 1)
  await waitLogCount(b, PAGE_SIZE)
  check('a password login row is highlighted', await b.run(() => document.querySelectorAll('[data-testid=security-log] tr.pwd').length === 1))

  await b.page.select('#sec-machine', WARNING)
  await waitLogCount(b, PAGE_SIZE)
  check('a new filter goes back to page 1 (it was on page 3)', (await showing(b)).startsWith('Showing 1 to 50 of '))
  await goToPage(b, 2)
  await waitLogCount(b, FAILED_ROWS_WARNING + 1 - PAGE_SIZE)
  check('the machine filter narrows the log to that machine', await b.run(() => [...document.querySelectorAll('[data-testid=security-log] td[data-label=Machine]')].every((cell) => cell.textContent === 'gpu-pc')))
  check('the filter is kept in the address', (await b.run(() => location.hash)).includes('machine=gpu-pc'))
  await b.page.select('#sec-type', 'login')
  await waitLogCount(b, 1)
  check('the type filter narrows it further', (await pageText(b)).includes('Successful login'))
  await b.page.select('#sec-machine', '')
  await b.page.select('#sec-type', 'blocked')
  await waitLogCount(b, BLOCK_ROWS)
  await b.page.select('#sec-type', '')
  await b.type('#sec-search', NEEDLE_ADDRESS)
  await waitLogCount(b, 1)
  check('the text search finds an address', (await pageText(b)).includes(NEEDLE_ADDRESS))
  await b.shot('security-filtered-desktop-light.png', true)
  await b.type('#sec-search', 'no-such-user-anywhere')
  await b.until(() => document.querySelector('[data-testid=log-empty]') !== null, { timeout: SHORT_WAIT_MS })
  check('a search with no match says so in plain words', (await pageText(b)).includes('No events match these filters in this time range.'))
  await b.type('#sec-search', '')

  await b.page.goto(`${base}/#/security?range=24h`, { waitUntil: 'networkidle0' })
  await b.until((selector) => document.querySelectorAll(selector).length > 0 && document.querySelectorAll(selector).length < 90, { timeout: SHORT_WAIT_MS }, LOG_ROWS)
  check('a shorter time range shows fewer rows', (await logCount(b)) < TOTAL_ROWS)
  await open(b, base, '/security?range=90d')
  await b.page.select('[data-testid=page-size]', '25')
  await waitLogCount(b, 25)
  check('the page size select changes the page, and the choice is kept after a reload', await (async () => {
    const fresh = (await showing(b)) === `Showing 1 to 25 of ${TOTAL_ROWS}`
    await open(b, base, '/security?range=90d')
    await waitLogCount(b, 25)
    return fresh && (await b.run(() => document.querySelector<HTMLSelectElement>('[data-testid=page-size]')?.value)) === '25'
  })())
  await b.shot('security-log-pages-desktop-light.png', true)
  await b.page.select('[data-testid=page-size]', '100')
  await waitLogCount(b, 100)
  check('page size 100 shows 100 rows of 130 on two pages', (await showing(b)) === `Showing 1 to 100 of ${TOTAL_ROWS}`)
  await b.page.select('[data-testid=page-size]', String(PAGE_SIZE))
  await waitLogCount(b, PAGE_SIZE)
}

async function hostile(b: Browse, base: string) {
  await open(b, base, '/security?range=90d&machine=gpu-pc')
  await waitLogCount(b, PAGE_SIZE)
  const text = await pageText(b)
  check('a hostile user name is shown as text', text.includes(HOSTILE_NAME))
  check('it made no element and ran nothing', await b.run(() => document.querySelector('.body script, .body img') === null && !('__pwned' in window)))
  check('an image tag used as a name is only text too, in the top list', (await b.run(() => document.querySelector<HTMLElement>('[data-testid=top-users]')?.innerText ?? '')).includes(HOSTILE_IMG) && (await b.run(() => document.querySelectorAll('.body [onerror]').length === 0)))
}

async function notCollected(b: Browse, base: string, standIn: SecurityStandIn) {
  standIn.missing = true
  await open(b, base, '/security')
  check('when the parent has no security API the banner says nothing is watched', (await pageText(b)).includes(NOT_COLLECTED))
  check('every machine is listed and every machine is Not watched', JSON.stringify(await machineRowIds(b)) === JSON.stringify([HEALTHY, WARNING, MAC, OLD_HELPER]) && (await b.run(() => document.querySelectorAll('[data-testid=not-watched]').length)) === 4)
  check('there are no fake numbers: no chart, no top lists, no blocked list, an honest empty log', await b.run(() => document.querySelector('[data-testid^=chart-]') === null && document.querySelector('[data-testid=top-users]') === null && document.querySelector('[data-testid=log-missing]') !== null))
  const text = await pageText(b)
  check('the sample banner and the sample machines are not shown without the preview address', (await b.run(() => document.querySelector('[data-testid=preview-banner]') === null)) && SAMPLE_MACHINES.every((name) => !text.includes(name)))
  await b.shot('security-real-404-desktop-light.png', true)
}

async function preview(b: Browse, base: string) {
  await open(b, base, '/security?preview=1&range=90d')
  const text = await pageText(b)
  check('the preview shows the loud sample banner', text.includes(SAMPLE_BANNER) && (await b.run(() => document.querySelector('[data-testid=preview-banner]')?.getAttribute('role') === 'alert')))
  check('the banner stays at the top of the screen when the page is scrolled', await b.run(async () => {
    window.scrollTo(0, 600)
    await new Promise((resolve) => setTimeout(resolve, 100))
    const top = document.querySelector('[data-testid=preview-banner]')?.getBoundingClientRect().top ?? -1
    window.scrollTo(0, 0)
    return top === 0
  }))
  check('the sample has the four machines, one that never reported', JSON.stringify(await b.run(() => [...document.querySelectorAll('[data-testid=security-machines] tbody tr')].map((row) => row.querySelector('td')?.textContent?.trim()))) === JSON.stringify(SAMPLE_MACHINES))
  check('the Mac Mini is Not watched, the RTX PC shows about 96,000 failed logins', (await rowText(b, 'mac-mini')).toLowerCase().includes('not watched') && /9\d,\d{3}/.test(await rowText(b, 'rtx-5090-pc')))
  check('the DGX Spark has password login on (a warning)', await b.run(() => document.querySelector('tr[data-machine=dgx-spark] [data-check=password_login]')?.getAttribute('data-state') === 'warning'))
  check('the sample log has a page of rows and page numbers', (await logCount(b)) === PAGE_SIZE && (await b.run(() => document.querySelector('[data-testid=pagination]') !== null)))
  check('the sample keeps the preview switch when the range changes', await (async () => {
    await b.click('30 d')
    await b.until(() => location.hash.includes('range=30d'), { timeout: SHORT_WAIT_MS })
    return (await b.run(() => location.hash)).includes('preview=1')
  })())
  await b.shot('security-preview-desktop-light.png', true)
}

async function previewLink(b: Browse, base: string) {
  await open(b, base, '/security')
  await b.page.click('[data-testid=preview-link]')
  await b.until(() => document.querySelector('[data-testid=preview-banner]') !== null, { timeout: SHORT_WAIT_MS })
  check('the "Preview with sample data" link opens the preview', (await b.run(() => location.hash)).includes('preview=1'))
  await b.page.click('[data-testid=preview-banner] a')
  await b.until(() => document.querySelector('[data-testid=preview-banner]') === null, { timeout: SHORT_WAIT_MS })
  check('"Leave the preview" goes back to the real page', !(await b.run(() => location.hash)).includes('preview'))
}

async function cardBadges(b: Browse, base: string) {
  await b.page.goto(`${base}/#/machines`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelectorAll('article.card').length >= 4, { timeout: SHORT_WAIT_MS })
  const href = (name: string) => b.run((wanted) => [...document.querySelectorAll('article.card')].find((card) => card.querySelector('.nm')?.textContent === wanted)?.querySelector('a[data-security-badge]')?.getAttribute('href') ?? null, name)
  check('a machine card badge links to the Security page for that machine', (await href(HEALTHY)) === '#/security?machine=ubuntu-box', String(await href(HEALTHY)))
  check('a machine that does not report has no badge', (await href(OLD_HELPER)) === null)
  await b.shot('security-list-badges-desktop-light.png', true)
  await b.run(() => document.querySelector<HTMLAnchorElement>('a[data-security-badge]')?.click())
  await b.until(() => location.hash.startsWith('#/security?machine='), { timeout: SHORT_WAIT_MS })
  check('pressing the badge opens Security with the log narrowed to that machine', (await b.run(() => document.querySelector<HTMLSelectElement>('#sec-machine')?.value)) !== '')
}

async function phone(page: Page, b: Browse, base: string, standIn: SecurityStandIn) {
  await page.setViewport(SIZES.phone)
  standIn.missing = false
  await open(b, base, '/security?range=90d')
  await expectNoSideScroll(b, 'Security, real data, phone')
  await b.shot('security-real-phone-light.png', true)
  await open(b, base, '/security?preview=1')
  await expectNoSideScroll(b, 'Security, preview, phone')
  await b.shot('security-preview-phone-light.png', true)
  standIn.missing = true
  await open(b, base, '/security')
  await expectNoSideScroll(b, 'Security, not collected, phone')
  await b.shot('security-real-404-phone-light.png', true)
  await page.goto(`${base}/#/machines`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelectorAll('article.card').length >= 4, { timeout: SHORT_WAIT_MS })
  await expectNoSideScroll(b, 'machine list with badges, phone')
  await b.shot('security-list-badges-phone-light.png', true)
}

const errors: string[] = []
const standIn: SecurityStandIn = { missing: false }
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const parent = startFakeParent({ chatsBuilt: 0, dist: panelDist, machines: securityMachines(), routes: securityRoutes(standIn) })
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (403|404|409)/.test(message.text()) && errors.push(message.text()))
  const b = browse(page)
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await sidebar(b, parent.base)
  await machinesTable(b, parent.base)
  await eventLog(b, parent.base)
  await hostile(b, parent.base)
  await cardBadges(b, parent.base)
  await previewLink(b, parent.base)
  await notCollected(b, parent.base, standIn)
  await preview(b, parent.base)
  await phone(page, b, parent.base, standIn)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.stop()
}
finish()
