// The Security tab in a real browser against a stand-in parent with four machines: a healthy Linux one, one with warnings, a Mac, and one whose helper does not report.
// Checks that the tab opens from the machine page, every block shows, warnings are marked, a hostile user name is only text, a machine that does not report says so
// (no zeros), nothing scrolls sideways at phone width, and the machine card carries its badge. Pictures at desktop and phone width, light.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/security.e2e.ts   (needs a built panel and Google Chrome)
import puppeteer, { type Page } from 'puppeteer-core'
import { HEALTHY, HOSTILE_IMG, HOSTILE_NAME, MAC, OLD_HELPER, WARNING, securityMachines } from './security/data.ts'
import { startFakeParent } from './machine/fake-parent.ts'
import { SHORT_WAIT_MS, expectNoSideScroll, openMachine, openTab } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 400, height: 844 } }
const BLOCKS = ['Baseline', 'Summary', 'Blocked now', 'Names the bots try', 'Successful logins']
const TAB = 'Security'

const blockLabels = (b: Browse) => b.run(() => [...document.querySelectorAll('section.tile')].map((tile) => tile.getAttribute('aria-label')))
const stateOf = (b: Browse, id: string) => b.run((check_) => document.querySelector(`[data-check=${check_}]`)?.getAttribute('data-state') ?? null, id)
const inTab = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[role=tabpanel]:not([hidden])')?.innerText ?? '')

async function openSecurity(b: Browse, base: string, id: string) {
  await openMachine(b, base, id)
  await openTab(b, TAB)
  await b.until(() => !!document.querySelector('section[aria-label=Security]'), { timeout: SHORT_WAIT_MS })
}

async function healthy(b: Browse, base: string) {
  await openSecurity(b, base, HEALTHY)
  check('the Security tab opens from the machine page and is the selected tab', (await b.run(() => document.querySelector('[role=tab][aria-selected=true]')?.textContent?.trim())) === TAB)
  check('every block is there, top to bottom', JSON.stringify(await blockLabels(b)) === JSON.stringify(BLOCKS), JSON.stringify(await blockLabels(b)))
  /** Small headings are drawn in capitals; compare without letter case. */
  const text = (await inTab(b)).toLowerCase()
  check('the baseline has six rows, all ok on a healthy machine', (await b.run(() => [...document.querySelectorAll('[data-check]')].map((row) => row.getAttribute('data-state')).join())) === 'ok,ok,ok,ok,ok,ok')
  check('the summary shows the three windows and the real-sized numbers', ['24 hours', '7 days', '30 days', '96,000'].every((part) => text.includes(part)))
  check('the chart has one bar for each of the 17 reported days', (await b.run(() => document.querySelectorAll('[data-testid=security-bars] rect').length)) === 17)
  check('the tallest bar fills the chart, so the bars are to scale', await b.run(() => {
    const heights = [...document.querySelectorAll('[data-testid=security-bars] rect')].map((bar) => Number(bar.getAttribute('height')))
    return Math.max(...heights) === 80 && heights.every((height) => height > 0)
  }))
  check('the blocked table lists the addresses with attempts', text.includes('185.224.128.17') && text.includes('blocked since') && text.includes('blocked until'))
  check('the user names the bots try are listed, biggest first, at most eight', text.indexOf('ubuntu') < text.indexOf('postgres') && !text.includes('ftpuser'))
  check('the logins are all by key on a healthy machine', await b.run(() => document.querySelectorAll('tr[data-method=key]').length === 3 && document.querySelectorAll('tr[data-method=password]').length === 0))
  check('there is no unblock button (read only)', !(await b.run(() => [...document.querySelectorAll('[role=tabpanel]:not([hidden]) button')].some((button) => /unblock|ban/i.test(button.textContent ?? '')))))
  await b.shot('security-healthy-desktop-light.png', true)
}

async function warnings(b: Browse, base: string) {
  await openSecurity(b, base, WARNING)
  check('password login on is a warning that says "Turn off password login"', (await stateOf(b, 'password_login')) === 'warning' && (await inTab(b)).includes('Turn off password login'))
  check('no ban tool is a warning', (await stateOf(b, 'ban_tool')) === 'warning')
  check('firewall off and pending updates are warnings; an unsaid check is unknown', (await stateOf(b, 'firewall')) === 'warning' && (await stateOf(b, 'pending_updates')) === 'warning' && (await stateOf(b, 'starts_after_reboot')) === 'unknown')
  check('the empty blocked list is honest that no tool is blocking', (await b.run(() => document.querySelector('[data-testid=blocked-empty]')?.textContent ?? '')).includes('does not mean nobody is knocking'))
  check('a password login row is highlighted as a warning', await b.run(() => document.querySelector('tr[data-method=password] .tag.warn') !== null))
  const shown = await inTab(b)
  check('a hostile user name is shown as text', shown.includes(HOSTILE_NAME) && shown.includes(HOSTILE_IMG))
  check('a hostile user name made no element and ran nothing', await b.run(() => document.querySelector('[role=tabpanel]:not([hidden]) script, [role=tabpanel]:not([hidden]) img') === null && !('__pwned' in window)))
  await b.shot('security-warning-desktop-light.png', true)
}

async function mac(b: Browse, base: string) {
  await openSecurity(b, base, MAC)
  check('a Mac says the ban tool is not available, and it is not a warning', (await stateOf(b, 'ban_tool')) === 'unknown' && (await inTab(b)).includes('Not available'))
  check('a Mac counts failed logins and shows a dash for blocked addresses', (await inTab(b)).includes('–'))
}

async function notReporting(b: Browse, base: string) {
  await openSecurity(b, base, OLD_HELPER)
  const text = await inTab(b)
  check('a machine that does not report says "Not reporting yet"', text.includes('Not reporting yet'))
  check('it warns that a machine that does not report is not being watched', text.includes('A machine that does not report is not being watched'))
  check('there are no blocks and no numbers at all, so no fake zeros', (await blockLabels(b)).length === 0 && !/\d/.test(text.replace(/\s/g, '')))
  await b.shot('security-not-reporting-desktop-light.png', true)
}

async function cardBadges(b: Browse, base: string) {
  await b.page.goto(`${base}/#/machines`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelectorAll('article.card').length >= 4, { timeout: SHORT_WAIT_MS })
  const badge = (name: string) => b.run((wanted) => [...document.querySelectorAll('article.card')].find((card) => card.querySelector('.nm')?.textContent === wanted)?.querySelector('[data-security-badge]')?.textContent?.trim() ?? null, name)
  check('a healthy machine card shows "12 blocked · 7 d"', (await badge(HEALTHY)) === '12 blocked · 7 d', String(await badge(HEALTHY)))
  check('a machine with a warning shows the warning dot', ((await badge(WARNING)) ?? '').startsWith('●'), String(await badge(WARNING)))
  check('the Mac card shows a warning-free badge or none, never a dot', !((await badge(MAC)) ?? '').startsWith('●'))
  check('a machine that does not report has no badge', (await badge(OLD_HELPER)) === null)
  await b.shot('security-list-badges-desktop-light.png', true)
}

async function phone(page: Page, b: Browse, base: string) {
  await page.setViewport(SIZES.phone)
  for (const [id, name] of [[HEALTHY, 'healthy'], [WARNING, 'warning'], [OLD_HELPER, 'not-reporting']]) {
    await openSecurity(b, base, id ?? HEALTHY)
    await expectNoSideScroll(b, `Security, ${name}, phone`)
    await b.shot(`security-${name}-phone-light.png`, true)
  }
  await page.goto(`${base}/#/machines`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelectorAll('article.card').length >= 4, { timeout: SHORT_WAIT_MS })
  await expectNoSideScroll(b, 'machine list with badges, phone')
  await b.shot('security-list-badges-phone-light.png', true)
}

const errors: string[] = []
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const parent = startFakeParent({ chatsBuilt: 0, dist: panelDist, machines: securityMachines() })
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (403|404|409)/.test(message.text()) && errors.push(message.text()))
  const b = browse(page)
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await healthy(b, parent.base)
  await warnings(b, parent.base)
  await mac(b, parent.base)
  await notReporting(b, parent.base)
  await cardBadges(b, parent.base)
  await phone(page, b, parent.base)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.stop()
}
finish()
