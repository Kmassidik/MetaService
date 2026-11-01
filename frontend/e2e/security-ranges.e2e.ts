// The short time ranges (1 h, 6 h, 12 h, 24 h) of the Security page and the Update helper button of a Not watched row, in a real browser against the stand-in parent.
// Checks: the seven range buttons, the ten-minute chart (bars to scale, missing buckets draw nothing, caption, axis in the Asia/Jakarta zone and in UTC), the range wording,
// the old day chart for 7 d, the Not watched row for an online machine with and without an update, an offline machine, a machine that reports, the button flow, and phone width.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/security-ranges.e2e.ts   (needs a built panel and Google Chrome)
import puppeteer, { type Page } from 'puppeteer-core'
import { SHORT_BUCKETS, securityRoutes, type SecurityStandIn } from './security/api.ts'
import { HEALTHY, machine, securityMachines } from './security/data.ts'
import { startFakeParent, type HelperScenario } from './machine/fake-parent.ts'
import { SHORT_WAIT_MS, expectNoSideScroll } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'
import type { Json } from './support/json.ts'

const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 400, height: 844 } }
const OWNER_ZONE = 'Asia/Jakarta'
const OWNER_OFFSET_MS = 7 * 3_600_000
const RANGE_LABELS = '1 h|6 h|12 h|24 h|7 d|30 d|90 d'
const PHRASES: Record<string, string> = { '1h': 'in the last hour', '6h': 'in the last 6 hours', '12h': 'in the last 12 hours', '24h': 'in the last 24 hours' }
const FIRST_TICK_COUNT: Record<string, number> = { '1h': 6, '6h': 6, '12h': 6, '24h': 8 }
const TOP_BAR = 60
const OLD = 'a'.repeat(64)
const NEW = 'b'.repeat(64)
const UPDATED_TEXT = 'The helper was replaced with the newest one and it is running. Your VMs keep running.'
const STALE = 'dgx-old'
const CURRENT = 'dgx-current'
const AWAY = 'mac-away'
const OFFLINE_LINE = 'The machine is offline.'
const STALE_LINE = 'No security data yet: its helper may be old'
const BUTTON = 'Update helper'
const UPDATING = 'Updating…'

const pad = (value: number): string => String(value).padStart(2, '0')
const clock = (ms: number, zoneOffsetMs: number): string => { const date = new Date(ms + zoneOffsetMs); return `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}` }

async function open(b: Browse, base: string, hash: string) {
  await b.page.goto(`${base}/#${hash}`, { waitUntil: 'networkidle0' })
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Security' && document.querySelector('[data-testid=security-machines]') !== null, { timeout: SHORT_WAIT_MS })
}

const lastBucketStart = (b: Browse, range: string) => b.run(async (wanted) => {
  const reply = await (await fetch(`/api/security/overview?range=${wanted}`)).json()
  return (reply.buckets as { start: string }[]).map((bucket) => Date.parse(bucket.start)).sort((a, c) => c - a)[0] ?? 0
}, range)

const axisLabels = (b: Browse) => b.run(() => [...(document.querySelector('[data-testid=bucket-axis]')?.querySelectorAll('span') ?? [])].map((span) => span.textContent ?? ''))
const clickTime = (b: Browse, mode: 'local' | 'utc') => b.run((wanted) => document.querySelector<HTMLButtonElement>(`[data-testid=time-mode] [data-mode=${wanted}]`)?.click(), mode)

async function buttons(b: Browse, base: string) {
  await open(b, base, '/security')
  check('the page offers 1 h | 6 h | 12 h | 24 h | 7 d | 30 d | 90 d', (await b.run(() => [...document.querySelectorAll('.segmented[aria-label="Time range"] button')].map((button) => button.textContent?.trim()).join('|'))) === RANGE_LABELS)
  for (const range of Object.keys(SHORT_BUCKETS)) {
    await open(b, base, '/security')
    await b.run((wanted) => document.querySelector<HTMLButtonElement>(`[data-range="${wanted}"]`)?.click(), range)
    await b.until((wanted) => location.hash.includes(`range=${wanted}`) && document.querySelector('[data-testid=bucket-chart]') !== null, { timeout: SHORT_WAIT_MS }, range)
    check(`${range}: its button is pressed and the address keeps the range`, await b.run((wanted) => document.querySelector(`[data-range="${wanted}"]`)?.getAttribute('aria-pressed') === 'true', range))
  }
}

async function shortRange(b: Browse, base: string, range: string) {
  const count = SHORT_BUCKETS[range] ?? 0
  await open(b, base, `/security?range=${range}`)
  await b.until(() => document.querySelector('[data-testid=bucket-chart]') !== null, { timeout: SHORT_WAIT_MS })
  const chart = await b.run(() => {
    const figures = [...document.querySelectorAll('[data-testid=bucket-chart] figure')]
    const heights = figures.flatMap((figure) => [...figure.querySelectorAll('rect')].map((bar) => Number(bar.getAttribute('height'))))
    return { figures: figures.length, bars: figures.map((figure) => figure.querySelectorAll('rect').length), tallest: Math.max(...heights), scale: document.querySelector('.scale')?.textContent ?? '', summary: document.querySelector('[data-testid=range-summary]')?.textContent ?? '' }
  })
  check(`${range}: one chart for each machine with counts, drawn from ten-minute buckets`, chart.figures === 3, JSON.stringify(chart))
  check(`${range}: a missing bucket draws nothing (fewer bars than buckets), and the tallest bar fills its chart on the shared scale`, chart.bars.every((bars) => bars > 0 && bars < count) && chart.tallest === TOP_BAR, JSON.stringify(chart))
  check(`${range}: the caption says each bar is 10 minutes and the summary uses the range words`, chart.scale.includes('each bar is 10 minutes') && !chart.scale.includes('UTC day') && chart.summary.endsWith(`${PHRASES[range]}.`), JSON.stringify(chart))
  const text = await b.run(() => document.body.innerText)
  check(`${range}: the page shows no "UTC days" caption`, !text.includes('UTC days'))
  const last = await lastBucketStart(b, range)
  const local = await axisLabels(b)
  check(`${range}: the axis has ${FIRST_TICK_COUNT[range]} labels like 15:40 in the Asia/Jakarta zone, the last one ending the chart`, local.length === FIRST_TICK_COUNT[range] && local.every((label) => /^\d\d:\d\d$/.test(label)) && (range !== '1h' || local.at(-1) === clock(last, OWNER_OFFSET_MS)), JSON.stringify({ local, last: new Date(last).toISOString() }))
  if (range === '1h') {
    const stepped = local.map((label) => Number(label.slice(3)))
    check('1 h: a label every 10 minutes', stepped.every((minute, index) => index === 0 || (minute - (stepped[index - 1] ?? 0) + 60) % 60 === 10), JSON.stringify(local))
  }
  await clickTime(b, 'utc')
  await b.until(() => document.querySelector('[data-testid=time-mode] [data-mode=utc]')?.getAttribute('aria-pressed') === 'true', { timeout: SHORT_WAIT_MS })
  const utc = await axisLabels(b)
  check(`${range}: UTC shows the same ticks seven hours earlier`, range !== '1h' || utc.at(-1) === clock(last, 0), JSON.stringify({ utc, last: new Date(last).toISOString() }))
  await b.shot(`security-${range}-utc-desktop-light.png`, true).catch(() => undefined)
  await clickTime(b, 'local')
}

async function longRange(b: Browse, base: string) {
  await open(b, base, '/security?range=7d')
  const state = await b.run(() => ({ axis: document.querySelector('[data-testid=chart-axis]')?.textContent ?? '', buckets: document.querySelector('[data-testid=bucket-chart]') !== null, summary: document.querySelector('[data-testid=range-summary]')?.textContent ?? '' }))
  check('7 d keeps the chart of UTC days and its caption', state.axis.includes('UTC days') && !state.buckets, JSON.stringify(state))
  check('7 d: the summary says in the last 7 days', state.summary.endsWith('in the last 7 days.'), state.summary)
  await b.shot('security-7d-desktop-light.png', true)
}

async function wording(b: Browse, base: string) {
  await open(b, base, '/security?range=6h')
  const lists = await b.run(() => ({ users: document.querySelector('[data-testid=top-users]') !== null, addresses: document.querySelector('[data-testid=top-addresses]') !== null }))
  check('6 h: the top lists are drawn', lists.users && lists.addresses)
  await b.shot('security-6h-desktop-light.png', true)
  await open(b, base, '/security?range=1h')
  await b.shot('security-1h-desktop-light.png', true)
  await open(b, base, '/security?range=12h')
  await b.shot('security-12h-desktop-light.png', true)
}

async function phone(page: Page, b: Browse, base: string) {
  await page.setViewport(SIZES.phone)
  for (const range of ['1h', '12h', '24h', '7d']) {
    await open(b, base, `/security?range=${range}`)
    await expectNoSideScroll(b, `Security ${range}, phone`)
    if (range !== '24h') await b.shot(`security-${range}-phone-light.png`, true)
  }
  check('at phone width the seven range buttons are all reachable', (await b.run(() => document.querySelectorAll('.segmented[aria-label="Time range"] button').length)) === 7)
}

const update = (available: boolean): Json => ({ agent_build: OLD, update: { available, current_build: OLD, newest_build: available ? NEW : OLD, reason: null } })

/** Four machines: the one that reports (with an update on offer, which must not show a button), an online one that does not report and has an update, one whose helper is current, and an offline one. */
export function notWatchedMachines(): Json[] {
  return [machine(HEALTHY, 'linux', update(true)), machine(STALE, 'linux', update(true)), machine(CURRENT, 'linux', update(false)), machine(AWAY, 'macos', { state: 'offline', ...update(true) })]
}

const rowHelp = (b: Browse, id: string) => b.run((wanted) => {
  const row = document.querySelector<HTMLElement>(`[data-testid=security-machines] tr[data-machine=${wanted}]`)
  return { line: row?.querySelector<HTMLElement>('[data-testid=not-watched-line]')?.innerText ?? null, button: row?.querySelector('[data-testid=not-watched-help] button')?.textContent?.trim() ?? null, outcome: row?.querySelector<HTMLElement>('[data-card-outcome]')?.innerText ?? null }
}, id)

async function notWatched(page: Page, b: Browse, base: string, updates: string[]) {
  await page.setViewport(SIZES.desktop)
  await open(b, base, '/security')
  const rows = { stale: await rowHelp(b, STALE), current: await rowHelp(b, CURRENT), away: await rowHelp(b, AWAY), reports: await rowHelp(b, HEALTHY) }
  check('an online machine that does not report says its helper may be old and offers Update helper', rows.stale.line === STALE_LINE && rows.stale.button === BUTTON, JSON.stringify(rows.stale))
  check('a machine whose helper is current gets the line and no button', rows.current.line === STALE_LINE && rows.current.button === null, JSON.stringify(rows.current))
  check('an offline machine says it is offline and has no button', rows.away.line === OFFLINE_LINE && rows.away.button === null, JSON.stringify(rows.away))
  check('a machine that reports never shows the line or the button', rows.reports.line === null && rows.reports.button === null, JSON.stringify(rows.reports))
  await b.shot('security-not-watched-button-desktop-light.png', true)
  await b.run((id) => document.querySelector<HTMLButtonElement>(`tr[data-machine=${id}] [data-testid=not-watched-help] button`)?.click(), STALE)
  await b.until((id, text) => document.querySelector(`tr[data-machine=${id}] [data-testid=not-watched-help] button`)?.textContent?.trim() === text, { timeout: SHORT_WAIT_MS }, STALE, UPDATING)
  check('while it works the button says Updating… and cannot be pressed again', await b.run((id) => document.querySelector<HTMLButtonElement>(`tr[data-machine=${id}] [data-testid=not-watched-help] button`)?.disabled === true, STALE))
  check('only that row is busy', (await rowHelp(b, CURRENT)).button === null && (await rowHelp(b, AWAY)).outcome === null)
  await b.until((id) => document.querySelector(`tr[data-machine=${id}] [data-card-outcome]`) !== null, { timeout: SHORT_WAIT_MS }, STALE)
  const done = await rowHelp(b, STALE)
  check('the result sentence from the parent shows in the row, the button is gone, and the parent was asked once for this machine', done.outcome?.includes(UPDATED_TEXT) === true && done.button === null && updates.join() === STALE, JSON.stringify({ done, updates }))
  await b.shot('security-not-watched-updated-desktop-light.png', true)
  await page.setViewport(SIZES.phone)
  await open(b, base, '/security')
  await expectNoSideScroll(b, 'Not watched rows, phone')
  await b.shot('security-not-watched-button-phone-light.png', true)
}

const errors: string[] = []
const standIn: SecurityStandIn = { missing: false }
const helper: HelperScenario = { build: OLD, newest: NEW, answer: { status: 200, body: { result: 'updated', message: UPDATED_TEXT } } }
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const parent = startFakeParent({ chatsBuilt: 0, dist: panelDist, machines: securityMachines(), routes: securityRoutes(standIn) })
const other = startFakeParent({ chatsBuilt: 0, dist: panelDist, helper, machines: notWatchedMachines(), routes: securityRoutes(standIn) })
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (403|404|409)/.test(message.text()) && errors.push(message.text()))
  const b = browse(page)
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await page.emulateTimezone(OWNER_ZONE)
  await buttons(b, parent.base)
  for (const range of Object.keys(SHORT_BUCKETS)) await shortRange(b, parent.base, range)
  await longRange(b, parent.base)
  await wording(b, parent.base)
  await phone(page, b, parent.base)
  await notWatched(page, b, other.base, other.updates)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.stop()
  other.stop()
}
finish()
