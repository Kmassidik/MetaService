// The Live tab's new layout and window, as browser checks: bordered cards of equal height in a 2 + 3 grid (one column on a phone), the "?" explanations,
// the per-core bars that are always there, and the Top processes window that fetches and draws the list only while it is open.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { CPU_NAMES, HOSTILE_NAME, PROCESS_COUNT, type StandIn } from './stand-in.ts'

const SHORT_WAIT_MS = 10000
const PAGE_POLL_MS = 5000
const SLACK_MS = 2500
const PANEL_GREY = 'rgb(229, 229, 229)'
const WORKER_ONE_MATCHES = 6
const PIXEL_TOLERANCE = 2
export const SIZES = { desktop: { width: 1280, height: 1000 }, laptop: { width: 1280, height: 800 }, phone: { width: 400, height: 900 } }

const closeTo = (a: number, b: number) => Math.abs(a - b) <= PIXEL_TOLERANCE

interface Box { left: number; top: number; width: number; height: number; border: string; borderColor: string }

/** The bordered cards inside one band of the Live tab, measured in the page. */
const cardsOf = (b: Browse, band: string) =>
  b.run((testid) => [...document.querySelectorAll<HTMLElement>(`[data-testid=${testid}] > section`)].map((card): Box => {
    const rect = card.getBoundingClientRect()
    const style = getComputedStyle(card)
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height, border: style.borderTopWidth, borderColor: style.borderTopColor }
  }), band)

export async function waitForNumbers(b: Browse) {
  await b.until(() => !!document.querySelector('[data-testid=gauge-cpu]'), { timeout: SHORT_WAIT_MS })
}

/** The new layout: a gauge row, then bands of two cards (CPU and Memory, System load and Disk speed, Network and GPU), the GPU charts, then the disk volumes. */
export async function cardsAreBorderedAndEqualInHeight(b: Browse, id: string, hasGpu: boolean) {
  const gauges = await cardsOf(b, 'gauge-row')
  const bands = [await cardsOf(b, 'band-cpu'), await cardsOf(b, 'band-load'), await cardsOf(b, 'band-network'), await cardsOf(b, 'band-volumes')]
  const all = [...gauges, ...bands.flat()]
  check(`${id}: every card has a 1px border in the panel's grey`, all.length > 0 && all.every((card) => card.border === '1px' && card.borderColor === PANEL_GREY), JSON.stringify(all.map((card) => [card.border, card.borderColor])))
  check(`${id}: the gauge row has ${hasGpu ? 'six (the GPU is the sixth)' : 'five'} cards of the same size, side by side`, gauges.length === (hasGpu ? 6 : 5) && gauges.every((card) => closeTo(card.width, gauges[0]?.width ?? -1) && closeTo(card.height, gauges[0]?.height ?? -1) && closeTo(card.top, gauges[0]?.top ?? -1)), JSON.stringify(gauges))
  const [cpuBand, loadBand, netBand, volumes] = bands
  for (const [name, band] of [['CPU and Memory', cpuBand], ['System load and Disk speed', loadBand]] as const) {
    check(`${id}: ${name} are two cards of the same width and height, 16 px apart`, band?.length === 2 && closeTo(band[0]?.width ?? 0, band[1]?.width ?? -1) && closeTo(band[0]?.height ?? 0, band[1]?.height ?? -1) && closeTo((band[1]?.left ?? 0) - ((band[0]?.left ?? 0) + (band[0]?.width ?? 0)), 16), JSON.stringify(band))
  }
  check(`${id}: Network ${hasGpu ? 'and the GPU share a row' : 'is alone, full width'}`, netBand?.length === (hasGpu ? 2 : 1) && closeTo(netBand?.[0]?.width ?? 0, hasGpu ? (cpuBand?.[0]?.width ?? -1) : (volumes?.[0]?.width ?? -1)), JSON.stringify(netBand))
  check(`${id}: the disk volumes come last, full width`, volumes?.length === 1 && (volumes[0]?.top ?? 0) > (netBand?.[0]?.top ?? Infinity), JSON.stringify(volumes))
}

/** The charts are drawn from the first look: the parent's hour is fetched once and the lines, legends and axes are there. */
export async function chartsAreFullWithHistory(b: Browse, world: StandIn, id: string, optional: 'full' | 'mac' | 'none', gpuCharts: readonly string[] = []) {
  check(`${id}: the history route was asked when the page opened`, (world.askedHistory[id] ?? 0) >= 1, String(world.askedHistory[id]))
  const drawn = await b.run(() => [...document.querySelectorAll<HTMLElement>('[data-testid=monitor-numbers] .chart')].map((chart) => ({
    name: chart.dataset.testid ?? '',
    lines: [...chart.querySelectorAll('svg path.line')].filter((path) => (path.getAttribute('d') ?? '').length > 40).length,
    xLabels: chart.querySelectorAll('.xlabel').length,
    yLabels: chart.querySelectorAll('.ylabel').length,
    legend: chart.querySelectorAll('.legend tbody tr').length,
    caption: chart.querySelector('.caption')?.textContent ?? '',
    summary: chart.querySelectorAll('.sr-only table tbody tr').length,
  })))
  const names = drawn.map((chart) => chart.name).join('|')
  const plain = optional === 'none' ? 'chart-CPU usage|chart-Memory usage|chart-System load|chart-Network speed' : 'chart-CPU usage|chart-Memory usage|chart-System load|chart-Disk speed|chart-Network speed'
  const expected = [plain, ...gpuCharts.map((name) => `chart-${name}`)].join('|')
  check(`${id}: the charts are CPU, memory, load, ${optional === 'none' ? '' : 'disk speed, '}network${gpuCharts.length > 0 ? `, ${gpuCharts.join(', ')}` : ''}`, names === expected, names)
  check(`${id}: every chart has lines on first load, time labels, a y axis, a legend and "per 10 seconds"`, drawn.every((chart) => chart.lines >= 1 && chart.xLabels >= 2 && chart.yLabels >= 2 && chart.legend >= 1 && chart.caption.includes('per 10 seconds') && chart.summary >= 1 && chart.summary === chart.legend), JSON.stringify(drawn))
  const legend = await b.run(() => Object.fromEntries([...document.querySelectorAll<HTMLElement>('[data-testid^=legend-]')].map((cell) => [cell.dataset.testid ?? '', cell.innerText])))
  check(`${id}: legend values are real numbers, not zeros or blanks`, [optional === 'none' ? 'legend-total' : 'legend-user', 'legend-1m', 'legend-in', 'legend-used'].every((key) => /\d/.test(legend[key] ?? '')), JSON.stringify(legend))
}

/** Cores against threads, grouped bars, and frequency and temperature only where the helper sends them. */
export async function topologyShowsCoresAndThreads(b: Browse, id: string, line: string, groups: number, threadsPerGroup: number, hasSpeed: boolean) {
  const found = await b.run(() => ({
    line: document.querySelector<HTMLElement>('[data-testid=cpu-topology]')?.innerText ?? '',
    groups: [...document.querySelectorAll('[data-testid=cpu-core]')].map((core) => core.querySelectorAll('.thread').length),
    labels: [...document.querySelectorAll('[data-testid=cpu-core] .thread')].slice(0, 2).map((bar) => bar.getAttribute('aria-label') ?? ''),
    speed: document.querySelector('[data-testid=cpu-frequency]') !== null,
    heat: document.querySelector('[data-testid=cpu-temperature]') !== null,
    name: document.querySelector<HTMLElement>('[data-testid=cpu-model]')?.innerText ?? null,
    text: document.body.innerText,
  }))
  check(`${id}: the CPU card says "${line}"`, found.line === line, found.line)
  check(`${id}: the CPU card names the CPU when the machine reports one, and shows nothing when it does not`, found.name === (CPU_NAMES[id] ?? null), String(found.name))
  check(`${id}: the thread bars are grouped by core (${groups} groups of ${threadsPerGroup})`, found.groups.length === groups && found.groups.every((count) => count === threadsPerGroup), found.groups.join(','))
  check(`${id}: a bar is named like "core 1 thread 1 · 12%", "core 1 · 12%" or (no core data) "CPU 1 · 12%"`, found.labels.every((label) => /^(core|CPU) \d+( thread \d+)? · \d+%$/.test(label)), found.labels.join('|'))
  check(`${id}: frequency and temperature ${hasSpeed ? 'are shown' : 'are left out, never shown as 0'}`, found.speed === hasSpeed && found.heat === hasSpeed && (hasSpeed || !/0 °C|0\.0 GHz/.test(found.text)))
}

export async function coresAreAlwaysShown(b: Browse, count: number) {
  const inCard = await b.run(() => document.querySelectorAll('section[aria-label=CPU] .thread').length)
  check(`the ${count} per-thread bars are visible inside the CPU card without pressing anything`, inCard === count, String(inCard))
  check('there is no "cores" fold button any more', !(await b.run(() => [...document.querySelectorAll('button')].some((button) => /cores\s*[▾▴]/.test(button.textContent ?? '')))))
}

export async function oneColumnWithoutSidewaysScroll(page: Page, b: Browse, id: string) {
  await page.setViewport(SIZES.phone)
  await wait(300)
  const all = await b.run(() => [...document.querySelectorAll<HTMLElement>('[data-testid=monitor-numbers] section.card')].filter((card) => card.parentElement?.dataset.testid?.startsWith('band') || card.parentElement?.dataset.testid === 'gauge-facts').map((card) => {
    const rect = card.getBoundingClientRect()
    return { left: rect.left, width: rect.width, top: rect.top }
  }))
  check(`${id}: at 400 px the charts and facts are each on their own row, full width`, all.length >= 6 && all.every((card) => closeTo(card.left, all[0]?.left ?? -1) && closeTo(card.width, all[0]?.width ?? -1)) && all.every((card, index) => index === 0 || card.top > (all[index - 1]?.top ?? 0)))
  check(`${id}: no sideways scroll at 400 px`, await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  await b.shot(`live-${id}-phone.png`, true)
  await page.setViewport(SIZES.desktop)
  await wait(300)
}

/** The card of that name, not the gauge that shares the name. */
const cardOf = (label: string) => `section[aria-label="${label}"]:has(button[aria-expanded])`
const questionButton = (label: string) => `${cardOf(label)} button[aria-expanded]`

export async function helpButtonsToggleTheExplanations(b: Browse) {
  const openState = (label: string) => b.run((selector) => document.querySelector(selector)?.getAttribute('aria-expanded'), questionButton(label))
  const sectionText = (label: string) => b.run((selector) => document.querySelector(selector)?.textContent ?? '', cardOf(label))
  check('the "?" buttons exist on CPU, Memory and System load and are closed by default', (await openState('CPU')) === 'false' && (await openState('Memory')) === 'false' && (await openState('System load')) === 'false')
  check('the long sentences are not in the cards while closed', !(await b.text()).includes('Load is how many programs') && !(await b.text()).includes('Cached memory holds'))
  await b.page.click(questionButton('System load'))
  check('pressing "?" on System load shows the load sentence inside the card', (await openState('System load')) === 'true' && (await sectionText('System load')).includes('Load is how many programs are waiting for a turn'))
  await b.page.click(questionButton('Memory'))
  check('pressing "?" on Memory shows the cached memory sentence inside the card', (await sectionText('Memory')).includes('Cached memory holds recently used files'))
  await b.page.click(questionButton('CPU'))
  check('pressing "?" on CPU explains user, system, nice and iowait', (await sectionText('CPU')).includes('user is programs'))
  await b.page.click(questionButton('System load'))
  await b.page.click(questionButton('Memory'))
  await b.page.click(questionButton('CPU'))
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

/** The window opens busiest first; the CPU and Memory headings sort, and say so with aria-sort. */
export async function windowSortsByCpuAndMemory(b: Browse) {
  const order = () => b.run(() => [...document.querySelectorAll('dialog[open] .procs .name')].slice(0, 3).map((cell) => cell.textContent))
  const sorts = () => b.run(() => [...document.querySelectorAll('dialog[open] th[aria-sort]')].map((th) => `${th.textContent?.trim().replace(/\s*↓/, '')}:${th.getAttribute('aria-sort')}`).join(','))
  check('the window opens sorted by CPU, busiest first', (await order())[0] === HOSTILE_NAME && (await sorts()) === 'CPU:descending,Memory:none', `${await order()} ${await sorts()}`)
  await b.page.click('dialog[open] [data-testid=sort-memory]')
  check('pressing Memory sorts by memory (the hostile program holds 5 GB) and moves aria-sort', (await order())[0] === HOSTILE_NAME && (await sorts()) === 'CPU:none,Memory:descending', `${await order()} ${await sorts()}`)
  check('by memory, the quiet workers come after node (1 GB) in size order', (await order()).join('|') === `${HOSTILE_NAME}|node|worker-3`, (await order()).join('|'))
  await b.page.click('dialog[open] [data-testid=sort-cpu]')
  check('pressing CPU sorts by CPU again', (await sorts()) === 'CPU:descending,Memory:none')
}

export async function windowRefreshesWhileOpenAndStopsWhenClosed(b: Browse, world: StandIn) {
  const open = world.askedWithProcesses.studio?.length ?? 0
  await wait(PAGE_POLL_MS + SLACK_MS)
  check('while the window is open the list is refreshed about every 2 s', (world.askedWithProcesses.studio?.length ?? 0) > open)
  await b.click('Close')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  check('closing removes the table from the page', !(await tableDrawn(b)))
  await wait(700)
  const closed = world.askedWithProcesses.studio?.length ?? 0
  await wait(PAGE_POLL_MS * 2 + SLACK_MS)
  check('after closing, nothing asks for the list any more', (world.askedWithProcesses.studio?.length ?? 0) === closed)
  check('the page keeps asking for the numbers, without the list', world.queries.at(-1) === '?processes=0')
}
