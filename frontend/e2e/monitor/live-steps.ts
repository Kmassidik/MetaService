// The Live tab's new layout and window, as browser checks: bordered cards of equal height in a 2 + 3 grid (one column on a phone), the "?" explanations,
// the per-core bars that are always there, and the Top processes window that fetches and draws the list only while it is open.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { HOSTILE_NAME, PROCESS_COUNT, type StandIn } from './stand-in.ts'

const SHORT_WAIT_MS = 10000
const PAGE_POLL_MS = 5000
const SLACK_MS = 2500
const PANEL_GREY = 'rgb(229, 229, 229)'
const WORKER_ONE_MATCHES = 6
const PIXEL_TOLERANCE = 2
const GRAPH_STRIP_PX = 64
export const SIZES = { desktop: { width: 1280, height: 1000 }, laptop: { width: 1280, height: 800 }, phone: { width: 400, height: 900 } }

const closeTo = (a: number, b: number) => Math.abs(a - b) <= PIXEL_TOLERANCE

interface Box { left: number; top: number; width: number; height: number; border: string; borderColor: string }

/** The cards of one row, measured in the page. */
const cardsOf = (b: Browse, row: 'upper' | 'lower') =>
  b.run((testid) => [...document.querySelectorAll<HTMLElement>(`[data-testid=${testid}] > section`)].map((card): Box => {
    const rect = card.getBoundingClientRect()
    const style = getComputedStyle(card)
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height, border: style.borderTopWidth, borderColor: style.borderTopColor }
  }), `cards-${row}`)

export async function waitForNumbers(b: Browse) {
  await b.until(() => !!document.querySelector('[data-testid=cpu-total]'), { timeout: SHORT_WAIT_MS })
}

export async function cardsAreBorderedAndEqualInHeight(b: Browse, id: string, expectLower: number) {
  const upper = await cardsOf(b, 'upper')
  const lower = await cardsOf(b, 'lower')
  const all = [...upper, ...lower]
  check(`${id}: every card has a 1px border in the panel's grey`, all.length > 0 && all.every((card) => card.border === '1px' && card.borderColor === PANEL_GREY), JSON.stringify(all.map((card) => [card.border, card.borderColor])))
  check(`${id}: the upper row is CPU and Memory, two cards of the same width and height`, upper.length === 2 && closeTo(upper[0]?.width ?? 0, upper[1]?.width ?? -1) && closeTo(upper[0]?.height ?? 0, upper[1]?.height ?? -1), JSON.stringify(upper))
  check(`${id}: the lower row has ${expectLower} cards of the same width and the same height`, lower.length === expectLower && lower.every((card) => closeTo(card.width, lower[0]?.width ?? -1) && closeTo(card.height, lower[0]?.height ?? -1)), JSON.stringify(lower))
  check(`${id}: the cards line up (same top in a row, a 16 px gap)`, upper.every((card) => closeTo(card.top, upper[0]?.top ?? -1)) && lower.every((card) => closeTo(card.top, lower[0]?.top ?? -1)) && closeTo((upper[1]?.left ?? 0) - ((upper[0]?.left ?? 0) + (upper[0]?.width ?? 0)), 16))
  const upperWidth = upper[0]?.width ?? 0
  const lowerWidth = lower[0]?.width ?? 0
  check(`${id}: ${expectLower === 3 ? 'three smaller cards are narrower than the two wide ones' : 'two lower cards are as wide as the two upper ones'}`, expectLower === 3 ? lowerWidth < upperWidth : closeTo(lowerWidth, upperWidth))
}

export async function graphsLineUp(b: Browse) {
  const strips = await b.run(() => [...document.querySelectorAll<HTMLElement>('[data-testid=cards-upper] .strip')].map((strip) => ({ height: strip.getBoundingClientRect().height, bottom: strip.getBoundingClientRect().bottom })))
  check('the graphs of CPU and Memory sit in strips of the same fixed height at the same level', strips.length === 2 && strips.every((strip) => closeTo(strip.height, GRAPH_STRIP_PX) && closeTo(strip.bottom, strips[0]?.bottom ?? -1)), JSON.stringify(strips))
  const nums = await b.run(() => ['[data-testid=cpu-total]', '[data-testid=memory-used]', '[data-testid=net-down]'].map((selector) => getComputedStyle(document.querySelector(selector) ?? document.body).fontVariantNumeric))
  check('the numbers use tabular figures', nums.every((value) => value.includes('tabular-nums')), nums.join('|'))
}

export async function coresAreAlwaysShown(b: Browse, count: number) {
  const inCard = await b.run(() => document.querySelectorAll('section[aria-label=CPU] .core').length)
  check(`the ${count} per-core bars are visible inside the CPU card without pressing anything`, inCard === count, String(inCard))
  check('there is no "cores" fold button any more', !(await b.run(() => [...document.querySelectorAll('button')].some((button) => /cores\s*[▾▴]/.test(button.textContent ?? '')))))
}

export async function oneColumnWithoutSidewaysScroll(page: Page, b: Browse, id: string) {
  await page.setViewport(SIZES.phone)
  await wait(300)
  const upper = await cardsOf(b, 'upper')
  const lower = await cardsOf(b, 'lower')
  const all = [...upper, ...lower]
  check(`${id}: at 400 px every card is on its own row, full width`, all.length >= 4 && all.every((card) => closeTo(card.left, all[0]?.left ?? -1) && closeTo(card.width, all[0]?.width ?? -1)) && all.every((card, index) => index === 0 || card.top > (all[index - 1]?.top ?? 0)))
  check(`${id}: no sideways scroll at 400 px`, await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await b.shot(`live-${id}-phone.png`, true)
  await page.setViewport(SIZES.desktop)
  await wait(300)
}

const questionButton = (label: string) => `section[aria-label="${label}"] button[aria-expanded]`

export async function helpButtonsToggleTheExplanations(b: Browse) {
  const openState = (label: string) => b.run((selector) => document.querySelector(selector)?.getAttribute('aria-expanded'), questionButton(label))
  const text = () => b.run(() => document.querySelector('section[aria-label=CPU]')?.textContent ?? '')
  check('the "?" buttons exist on CPU and Memory and are closed by default', (await openState('CPU')) === 'false' && (await openState('Memory')) === 'false')
  check('the long sentences are not in the cards while closed', !(await b.text()).includes('Load is how many programs') && !(await b.text()).includes('Cached memory holds'))
  await b.page.click(questionButton('CPU'))
  check('pressing "?" on CPU shows the load sentence inside the card', (await openState('CPU')) === 'true' && (await text()).includes('Load is how many programs are waiting for a turn'))
  await b.page.click(questionButton('Memory'))
  check('pressing "?" on Memory shows the cached memory sentence inside the card', (await b.run(() => document.querySelector('section[aria-label=Memory]')?.textContent ?? '')).includes('Cached memory holds recently used files'))
  await b.page.click(questionButton('CPU'))
  await b.page.click(questionButton('Memory'))
  check('pressing again closes them', (await openState('CPU')) === 'false' && !(await b.text()).includes('Load is how many programs'))
}

const processRows = (b: Browse) => b.run(() => document.querySelectorAll('dialog[open] .procs tbody tr').length)
const tableDrawn = (b: Browse) => b.run(() => document.querySelector('.procs') !== null)

export async function listIsNeverFetchedOrDrawnWhileTheWindowIsClosed(b: Browse, world: StandIn) {
  const before = world.askedWithProcesses.studio?.length ?? 0
  const queriesBefore = world.queries.length
  await wait(PAGE_POLL_MS * 2 + SLACK_MS)
  const newQueries = world.queries.slice(queriesBefore)
  check('while the window is closed the page asks again but never for the list', newQueries.length >= 1 && newQueries.every((query) => query === '?processes=0') && (world.askedWithProcesses.studio?.length ?? 0) === before, newQueries.join(' '))
  check('no process table is drawn while the window is closed', !(await tableDrawn(b)))
  check('the Live header has an outline "Top processes" button at the right, after the status note', await b.run(() => {
    const button = document.querySelector<HTMLElement>('[data-testid=processes-button]')
    const note = [...document.querySelectorAll<HTMLElement>('.head .note')][0]
    if (!button || !note) return false
    return button.classList.contains('line') && button.getBoundingClientRect().left >= note.getBoundingClientRect().right && Math.abs(button.getBoundingClientRect().top - note.getBoundingClientRect().top) < 30
  }))
}

export async function windowListsFifteenAndFilters(page: Page, b: Browse, world: StandIn) {
  const asked = world.askedWithProcesses.studio?.length ?? 0
  await b.click('Top processes')
  await b.until(() => document.querySelectorAll('dialog[open] .procs tbody tr').length > 1, { timeout: SHORT_WAIT_MS })
  check('opening the window asks the parent for the list (processes=1)', (world.askedWithProcesses.studio?.length ?? 0) > asked && world.queries.at(-1) === '?processes=1', world.queries.at(-1) ?? '')
  check('the window shows the top 15 programs', (await processRows(b)) === PROCESS_COUNT)
  check('the window says "Run by" and what it means', (await b.dialogText()).includes('"Run by" is the account that started the program.') && (await b.run(() => document.querySelector('dialog[open] .procs th:nth-child(2)')?.textContent)) === 'Run by')
  const cell = await b.run(() => ({ images: document.querySelectorAll('dialog[open] img, dialog[open] script').length, name: document.querySelector<HTMLElement>('dialog[open] .procs .name')?.textContent ?? '', user: document.querySelector<HTMLElement>('dialog[open] .procs .user')?.textContent ?? '' }))
  check('a hostile process name and account stay text in the window', cell.images === 0 && cell.name === HOSTILE_NAME && cell.user.startsWith('<script>'), JSON.stringify(cell))
  await b.shot('live-processes-modal-desktop.png')
  await b.page.type('dialog[open] input[type=search]', 'KURNIA')
  check('the filter narrows by account, ignoring letter case', (await b.run(() => [...document.querySelectorAll('dialog[open] .procs .name')].map((cell) => cell.textContent))).join() === 'node')
  await b.type('dialog[open] input[type=search]', 'worker-1')
  check('the filter narrows by name over all 15 programs', (await processRows(b)) === WORKER_ONE_MATCHES)
  await b.type('dialog[open] input[type=search]', 'zzz')
  check('a filter with no match says so', (await b.dialogText()).includes('No program matches that.'))
  await b.type('dialog[open] input[type=search]', '')
  await page.setViewport(SIZES.phone)
  await wait(300)
  await b.shot('live-processes-modal-phone.png')
  check('the window fits a phone: no sideways scroll', await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await page.setViewport(SIZES.desktop)
}

export async function windowRefreshesWhileOpenAndStopsWhenClosed(b: Browse, world: StandIn) {
  const open = world.askedWithProcesses.studio?.length ?? 0
  await wait(PAGE_POLL_MS + SLACK_MS)
  check('while the window is open the list is refreshed about every 5 s', (world.askedWithProcesses.studio?.length ?? 0) > open)
  await b.click('Close')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  check('closing removes the table from the page', !(await tableDrawn(b)))
  await wait(700)
  const closed = world.askedWithProcesses.studio?.length ?? 0
  await wait(PAGE_POLL_MS * 2 + SLACK_MS)
  check('after closing, nothing asks for the list any more', (world.askedWithProcesses.studio?.length ?? 0) === closed)
  check('the page keeps asking for the numbers, without the list', world.queries.at(-1) === '?processes=0')
}
