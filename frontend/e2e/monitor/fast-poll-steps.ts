// The faster refresh while a person watches the Live tab: a request about every 2 seconds, none when another tab or a hidden browser tab is shown,
// an immediate one on return, never two at once, a caption that says so, and the charts still growing by one point per 10 seconds.
import type { Page } from 'puppeteer-core'
import { openMachine, openTab } from '../machine/steps.ts'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import type { StandIn } from './stand-in.ts'
import { SIZES, waitForNumbers } from './live-steps.ts'

const CAPTION = 'live · refreshes every 2 s'
const WATCH_MS = 7000
const QUIET_MS = 4000
const MIN_ASKS_IN_WATCH = 3
const MAX_ASKS_IN_WATCH = 4
const RETURN_SETTLE_MS = 700
const CHART_SECONDS = 10
const SHOT_NAME = 'live-caption-desktop.png'
const CPU_LINE = '[data-testid="chart-CPU usage"] svg path.line'

const asks = (world: StandIn, id: string) => world.asked[id]?.length ?? 0

/** Makes the browser tab look hidden or shown to the page, the way the existing hidden-tab test does. */
export async function setVisible(b: Browse, visible: boolean) {
  await b.run((show) => {
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (show ? 'visible' : 'hidden') })
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => !show })
    document.dispatchEvent(new Event('visibilitychange'))
  }, visible)
}

/** The number of points the CPU chart draws: its line is one move plus one line segment per point (a gap starts a new move). */
const cpuChartPoints = (b: Browse) => b.run((selector) => (document.querySelector(selector)?.getAttribute('d') ?? '').split(/[ML]/).length - 1, CPU_LINE)

/** Counts the stats requests that are open at the same time in the page. */
function watchOverlap(page: Page) {
  let open = 0
  let most = 0
  const isStats = (url: string) => /\/api\/machines\/[^/]+\/stats\?/.test(url)
  page.on('request', (request) => {
    if (!isStats(request.url())) return
    open += 1
    most = Math.max(most, open)
  })
  const done = (request: { url: () => string }) => {
    if (isStats(request.url())) open -= 1
  }
  page.on('requestfinished', done)
  page.on('requestfailed', done)
  return () => most
}

async function captionAndRate(page: Page, b: Browse, world: StandIn) {
  const mostAtOnce = watchOverlap(page)
  await page.setViewport(SIZES.desktop)
  await openMachine(b, world.base, 'studio')
  await waitForNumbers(b)
  const caption = await b.run(() => document.querySelector<HTMLElement>('[data-testid=live-caption]')?.innerText ?? '')
  check('the Live header carries the grey caption "live · refreshes every 2 s"', caption === CAPTION, caption)
  check('the old line no longer says 5 s', !(await b.text()).includes('refreshes every 5'))
  await b.shot(SHOT_NAME)
  const pointsBefore = await cpuChartPoints(b)
  const asksBefore = asks(world, 'studio')
  await wait(WATCH_MS)
  const made = asks(world, 'studio') - asksBefore
  check('on the Live tab the stats route is asked 3 or 4 times in 7 seconds (about every 2 s), not once', made >= MIN_ASKS_IN_WATCH && made <= MAX_ASKS_IN_WATCH, String(made))
  const grown = (await cpuChartPoints(b)) - pointsBefore
  check('the charts grew by at most one point in 7 seconds (the 10 second grid), not one per ask', grown <= Math.ceil(WATCH_MS / 1000 / CHART_SECONDS) && grown < made, `${grown} new points for ${made} asks`)
  check('never two stats requests at once', mostAtOnce() === 1, String(mostAtOnce()))
}

async function otherTabStops(b: Browse, world: StandIn) {
  await openTab(b, 'VMs')
  await wait(RETURN_SETTLE_MS)
  const before = asks(world, 'studio')
  await wait(QUIET_MS)
  check('on the VMs tab no stats request is made for 4 seconds', asks(world, 'studio') === before, `${before} then ${asks(world, 'studio')}`)
  await openTab(b, 'Live')
  await wait(RETURN_SETTLE_MS)
  check('back on Live the stats route is asked at once', asks(world, 'studio') === before + 1, `${before} then ${asks(world, 'studio')}`)
}

async function hiddenBrowserTabStops(b: Browse, world: StandIn) {
  await setVisible(b, false)
  await wait(RETURN_SETTLE_MS)
  const before = asks(world, 'studio')
  await wait(QUIET_MS)
  check('a hidden browser tab makes no stats request for 4 seconds', asks(world, 'studio') === before, `${before} then ${asks(world, 'studio')}`)
  await setVisible(b, true)
  await wait(RETURN_SETTLE_MS)
  check('a shown browser tab asks at once and then keeps going', asks(world, 'studio') === before + 1, `${before} then ${asks(world, 'studio')}`)
  await wait(QUIET_MS)
  check('after the return the 2 second rhythm continues', asks(world, 'studio') >= before + 2, `${before} then ${asks(world, 'studio')}`)
}

/** The whole fast-refresh story on the machine 'studio'. */
export async function fastRefreshWhileWatching(page: Page, b: Browse, world: StandIn) {
  await captionAndRate(page, b, world)
  await otherTabStops(b, world)
  await hiddenBrowserTabStops(b, world)
}
