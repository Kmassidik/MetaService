// The live monitor in a real browser against a stand-in parent: numbers appear and change, a hidden tab stops asking and a shown one asks at once,
// an offline machine says so with its last numbers greyed, a hostile process name stays text, and the Machines list asks slower than the page.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/monitor.e2e.ts   (needs a built panel, Google Chrome, `bun install` in frontend/)
import puppeteer, { type Page } from 'puppeteer-core'
import { startStandIn, type StandIn } from './monitor/stand-in.ts'
import { cardsAreBorderedAndEqualInHeight, chartsAreFullWithHistory, coresAreAlwaysShown, helpButtonsToggleTheExplanations, listIsNeverFetchedOrDrawnWhileTheWindowIsClosed, oneColumnWithoutSidewaysScroll, SIZES, topologyShowsCoresAndThreads, waitForNumbers, windowListsFifteenAndFilters, windowRefreshesWhileOpenAndStopsWhenClosed, windowSortsByCpuAndMemory } from './monitor/live-steps.ts'
import { openMachine, openTab } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { noSideScroll, owlShown } from './support/owls.ts'
import { wait } from './support/net.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SHORT_WAIT_MS = 10000
const PAGE_POLL_MS = 5000
const LIST_POLL_MS = 15000
const TABS = ['Live', 'VMs', 'Environment', 'Activity']
const SLACK_MS = 2500

const cpuText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-testid=gauge-cpu]')?.innerText ?? '')
const calls = (world: StandIn, id: string) => world.asked[id]?.length ?? 0

async function setVisible(b: Browse, visible: boolean) {
  await b.run((show) => {
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (show ? 'visible' : 'hidden') })
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => !show })
    document.dispatchEvent(new Event('visibilitychange'))
  }, visible)
}

async function numbersAppear(b: Browse, world: StandIn) {
  await openMachine(b, world.base, 'studio')
  await waitForNumbers(b)
  const first = await cpuText(b)
  const text = await b.text()
  check('the monitor shows CPU, memory, disk, network and GPU cards and a Top processes button', ['cpu', 'memory', 'disk', 'network', 'gpu', 'top processes'].every((word) => text.toLowerCase().includes(word)))
  check('the process table is not on the Live tab', !text.includes('Run by') && !text.includes('worker-3'))
  check('uptime and the one small reserved line are shown', /up 1d 1h/.test(text) && text.includes('VMs have reserved 4 cores, 8 GB memory, 80 GB disk'))
  check('the old allocated headline is gone', !/Disk allocated|cores promised|whole building/.test(text))
  await b.until((before) => document.querySelector<HTMLElement>('[data-testid=gauge-cpu]')?.innerText !== before, { timeout: PAGE_POLL_MS + SLACK_MS }, first)
  check('the numbers change by themselves', (await cpuText(b)) !== first)
}

async function numbersUseTabularFigures(b: Browse) {
  const figures = await b.run(() => ['[data-testid=gauge-cpu]', '[data-testid=memory-used]', '[data-testid=net-down]', '[data-testid=process-count]'].map((selector) => getComputedStyle(document.querySelector(selector) ?? document.body).fontVariantNumeric))
  check('the numbers use tabular figures', figures.every((value) => value.includes('tabular-nums')), figures.join('|'))
  const count = await b.run(() => document.querySelector<HTMLElement>('[data-testid=process-count]')?.innerText ?? '')
  check('the big process count shows how many programs run', /^\d{3}$/.test(count), count)
}

/** A Mac with clusters, a 2-core 4-thread Linux box, and an 8-core Mac that sends none of the optional numbers. */
async function machinesWithOtherLayouts(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.laptop)
  await openMachine(b, world.base, 'mac')
  await waitForNumbers(b)
  await chartsAreFullWithHistory(b, world, 'mac', 'mac')
  await topologyShowsCoresAndThreads(b, 'mac', '4 performance + 6 efficiency', 10, 1, false)
  const states = await b.run(() => [...document.querySelectorAll('[data-testid^=legend-]')].map((cell) => cell.getAttribute('data-testid')).filter((key) => ['legend-user', 'legend-system', 'legend-nice', 'legend-iowait', 'legend-steal'].includes(key ?? '')).join(','))
  check('a Mac shows user, system and nice in the CPU legend and no iowait or steal', states === 'legend-user,legend-system,legend-nice', states)
  await openMachine(b, world.base, 'mini')
  await waitForNumbers(b)
  await topologyShowsCoresAndThreads(b, 'mini', '2 cores · 4 threads', 2, 2, true)
  await openMachine(b, world.base, 'bare')
  await waitForNumbers(b)
  await chartsAreFullWithHistory(b, world, 'bare', 'none')
  await topologyShowsCoresAndThreads(b, 'bare', '8 CPUs', 8, 1, false)
  const bare = await b.run(() => ({ none: document.querySelector<HTMLElement>('[data-testid=disk-io-none]')?.innerText ?? '', count: document.querySelector('[data-testid=process-count]') !== null, errors: document.querySelector('[data-testid=net-errors]') !== null, drops: document.querySelector('[data-testid=net-drops]') !== null, legend: [...document.querySelectorAll('[data-testid=legend-total]')].length }))
  check('without the optional numbers: the disk card says "Not available on this computer", and no process count, drops or errors are shown', bare.none === 'Not available on this computer.' && !bare.count && !bare.errors && !bare.drops, JSON.stringify(bare))
  check('without a CPU breakdown the chart draws the total in use', bare.legend === 1, JSON.stringify(bare))
  await b.shot('live-bare-laptop.png', true)
  await page.setViewport(SIZES.desktop)
}

async function hiddenTab(b: Browse, world: StandIn) {
  await setVisible(b, false)
  await wait(500)
  const before = calls(world, 'studio')
  await wait(PAGE_POLL_MS + SLACK_MS)
  check('a hidden tab stops asking', calls(world, 'studio') === before)
  await setVisible(b, true)
  await wait(700)
  check('a shown tab asks at once', calls(world, 'studio') === before + 1, `${before} then ${calls(world, 'studio')}`)
}

async function tabBarAndPolling(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.laptop)
  await openMachine(b, world.base, 'studio')
  await b.until(() => !!document.querySelector('[data-testid=gauge-cpu]'), { timeout: SHORT_WAIT_MS })
  check('the tab order is Live, VMs, Environment, Activity', (await b.run(() => [...document.querySelectorAll('[role=tab]')].map((tab) => tab.textContent?.trim().replace(/\s*\(\d+\)$/, '')).join('|'))) === 'Live|VMs|Environment|Activity')
  check('the tab bar is visible without scrolling at 1280x800 on a machine with a GPU', await b.run(() => (document.querySelector('[role=tablist]')?.getBoundingClientRect().bottom ?? Infinity) <= window.innerHeight))
  await b.shot('monitor-live-laptop.png')
  await openTab(b, 'VMs')
  await wait(500)
  const paused = calls(world, 'studio')
  await wait(PAGE_POLL_MS + SLACK_MS)
  check('polling pauses while another tab is shown', calls(world, 'studio') === paused, `${paused} then ${calls(world, 'studio')}`)
  await openTab(b, 'Live')
  await wait(700)
  check('Live asks at once when it is shown again', calls(world, 'studio') === paused + 1, `${paused} then ${calls(world, 'studio')}`)
  await page.setViewport(SIZES.desktop)
}

async function everyTabFitsAPhone(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.phone)
  for (const id of ['studio', 'mini', 'oldbox']) {
    await openMachine(b, world.base, id)
    for (const tab of TABS) {
      await openTab(b, tab)
      await b.shot(`monitor-${id}-${tab.toLowerCase()}-phone.png`, true)
      check(`no sideways scroll at 400 px: ${id}, ${tab}`, await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
    }
  }
  await page.setViewport(SIZES.desktop)
}

async function pageAsksEveryFiveSeconds(world: StandIn) {
  const stamps = world.asked.studio ?? []
  const gaps = stamps.slice(1).map((stamp, index) => stamp - (stamps[index] ?? 0)).filter((gap) => gap > 3000)
  check('the page asks about every 5 seconds', gaps.length > 0 && gaps.every((gap) => gap >= PAGE_POLL_MS - 500 && gap <= PAGE_POLL_MS + SLACK_MS), gaps.join(','))
}

async function oldHelper(b: Browse, world: StandIn) {
  await openMachine(b, world.base, 'oldbox')
  await b.until(() => document.body.innerText.includes('too old'), { timeout: SHORT_WAIT_MS })
  check('an old helper says it needs the update and shows no numbers', !(await b.run(() => !!document.querySelector('[data-testid=gauge-cpu]'))))
  await owlShown(b, 'offline', 'the helper-needs-the-update note')
}

async function offline(page: Page, b: Browse, world: StandIn) {
  await openMachine(b, world.base, 'mini')
  await b.until(() => !!document.querySelector('[data-testid=gauge-cpu]'), { timeout: SHORT_WAIT_MS })
  world.takeOffline('mini')
  await b.until(() => /offline, last seen/.test(document.body.innerText), { timeout: PAGE_POLL_MS + SLACK_MS })
  const grey = await b.run(() => getComputedStyle(document.querySelector('[data-testid=monitor-numbers]') ?? document.body).opacity)
  check('an offline machine says "offline, last seen" and keeps its last numbers greyed', Number(grey) < 1 && (await cpuText(b)) !== '' && !/^0%$/.test(await cpuText(b)))
  await owlShown(b, 'offline', 'the offline note')
  check('the offline machine still shows its last hour in the charts, greyed', await b.run(() => [...document.querySelectorAll('[data-testid=monitor-numbers] .chart svg path.line')].some((path) => (path.getAttribute('d') ?? '').length > 40)))
  await page.setViewport(SIZES.phone)
  await noSideScroll(b, 'the offline note on a phone')
  await b.shot('monitor-offline-phone.png', true)
  await page.setViewport(SIZES.desktop)
  await b.shot('monitor-offline-desktop.png', true)
}

async function listIsSlower(b: Browse, world: StandIn) {
  const start = Date.now()
  const before = calls(world, 'studio')
  await b.page.goto(`${world.base}/#/machines`, { waitUntil: 'networkidle0' })
  await b.until(() => !!document.querySelector('[data-testid=live-line]'), { timeout: SHORT_WAIT_MS })
  check('the list card shows a CPU and memory line', /CPU \d+% · memory \d+%/.test(await b.run(() => document.querySelector<HTMLElement>('[data-testid=live-line]')?.innerText ?? '')))
  await wait(LIST_POLL_MS + SLACK_MS - (Date.now() - start))
  const asked = calls(world, 'studio') - before
  check('the list asks once at first and again after about 15 seconds, not every 5', asked >= 2 && asked <= 3, `asked ${asked} times`)
  await b.shot('monitor-list-desktop.png', true)
}

async function pictures(page: Page, b: Browse, world: StandIn) {
  for (const [size, viewport] of Object.entries(SIZES)) {
    await page.setViewport(viewport)
    await openMachine(b, world.base, 'studio')
    await waitForNumbers(b)
    await b.shot(`monitor-studio-${size}.png`, true)
    check(`no sideways scroll at ${size} width`, await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  }
}

/** The machines without a GPU: Disk and Network share the lower row. A Mac and a plain Linux box. */
async function machinesWithoutGpu(page: Page, b: Browse, world: StandIn) {
  await page.setViewport(SIZES.laptop)
  for (const [id, cores] of [['mac', 10], ['mini', 4], ['bare', 8]] as const) {
    await openMachine(b, world.base, id)
    await waitForNumbers(b)
    await cardsAreBorderedAndEqualInHeight(b, id, false)
    await coresAreAlwaysShown(b, cores)
    await oneColumnWithoutSidewaysScroll(page, b, id)
    await page.setViewport(SIZES.laptop)
    await b.shot(`live-${id}-laptop.png`)
  }
  await page.setViewport(SIZES.desktop)
}

const errors: string[] = []
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const world = startStandIn(panelDist)
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('dialog', (dialog) => { errors.push(`a dialog opened: ${dialog.message()}`); void dialog.dismiss() })
  const b = browse(page)
  await page.setViewport(SIZES.desktop)
  await numbersAppear(b, world)
  await cardsAreBorderedAndEqualInHeight(b, 'studio', true)
  await chartsAreFullWithHistory(b, world, 'studio', 'full')
  const historyAsked = world.askedHistory.studio
  await topologyShowsCoresAndThreads(b, 'studio', '16 cores · 32 threads', 16, 2, true)
  await numbersUseTabularFigures(b)
  await coresAreAlwaysShown(b, 32)
  await helpButtonsToggleTheExplanations(b)
  await oneColumnWithoutSidewaysScroll(page, b, 'studio')
  await listIsNeverFetchedOrDrawnWhileTheWindowIsClosed(b, world)
  check('the history is asked once per page open, not with every 5 second poll', world.askedHistory.studio === historyAsked, `${historyAsked} then ${world.askedHistory.studio}`)
  await pageAsksEveryFiveSeconds(world)
  await windowListsFifteenAndFilters(page, b, world)
  await windowSortsByCpuAndMemory(b)
  await windowRefreshesWhileOpenAndStopsWhenClosed(b, world)
  await hiddenTab(b, world)
  await machinesWithoutGpu(page, b, world)
  await machinesWithOtherLayouts(page, b, world)
  await tabBarAndPolling(page, b, world)
  await everyTabFitsAPhone(page, b, world)
  await pictures(page, b, world)
  await oldHelper(b, world)
  await offline(page, b, world)
  await listIsSlower(b, world)
  check('no script errors and no alert from a hostile name', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  world.stop()
}
finish()
