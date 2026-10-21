// The live monitor in a real browser against a stand-in parent: numbers appear and change, a hidden tab stops asking and a shown one asks at once,
// an offline machine says so with its last numbers greyed, a hostile process name stays text, and the Machines list asks slower than the page.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/monitor.e2e.ts   (needs a built panel, Google Chrome, `bun install` in frontend/)
import puppeteer, { type Page } from 'puppeteer-core'
import { HOSTILE_NAME, startStandIn, type StandIn } from './monitor/stand-in.ts'
import { openMachine } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { wait } from './support/net.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SHORT_WAIT_MS = 10000
const PAGE_POLL_MS = 5000
const LIST_POLL_MS = 15000
const SIZES = { desktop: { width: 1280, height: 1000 }, phone: { width: 400, height: 900 } }
const SLACK_MS = 2500

const cpuText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-testid=cpu-total]')?.innerText ?? '')
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
  await b.until(() => !!document.querySelector('[data-testid=cpu-total]'), { timeout: SHORT_WAIT_MS })
  const first = await cpuText(b)
  const text = await b.text()
  check('the monitor shows CPU, memory, disk, network, GPU and processes', ['cpu', 'memory', 'disk', 'network', 'gpu', 'top processes'].every((word) => text.toLowerCase().includes(word)))
  check('32 cores draw 32 small bars in a compact grid', (await b.run(() => document.querySelectorAll('.core').length)) === 32)
  check('uptime and the one small reserved line are shown', /up 1d 1h/.test(text) && text.includes('VMs have reserved 4 cores, 8 GB memory, 80 GB disk'))
  check('the old allocated headline is gone', !/Disk allocated|cores promised|whole building/.test(text))
  await b.until((before) => document.querySelector<HTMLElement>('[data-testid=cpu-total]')?.innerText !== before, { timeout: PAGE_POLL_MS + SLACK_MS }, first)
  check('the numbers change by themselves', (await cpuText(b)) !== first)
}

async function hostileName(b: Browse) {
  const result = await b.run(() => ({
    images: document.querySelectorAll('.procs img, [data-testid=monitor] img').length,
    scripts: document.querySelectorAll('[data-testid=monitor] script').length,
    cell: document.querySelector<HTMLElement>('.procs .name')?.textContent ?? '',
  }))
  check('a hostile process name is shown as text, not as a tag', result.images === 0 && result.scripts === 0 && result.cell === HOSTILE_NAME, JSON.stringify(result))
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

async function pageAsksEveryFiveSeconds(world: StandIn) {
  const stamps = world.asked.studio ?? []
  const gaps = stamps.slice(1).map((stamp, index) => stamp - (stamps[index] ?? 0)).filter((gap) => gap > 3000)
  check('the page asks about every 5 seconds', gaps.length > 0 && gaps.every((gap) => gap >= PAGE_POLL_MS - 500 && gap <= PAGE_POLL_MS + SLACK_MS), gaps.join(','))
}

async function oldHelper(b: Browse, world: StandIn) {
  await openMachine(b, world.base, 'oldbox')
  await b.until(() => document.body.innerText.includes('too old'), { timeout: SHORT_WAIT_MS })
  check('an old helper says it needs the update and shows no numbers', !(await b.run(() => !!document.querySelector('[data-testid=cpu-total]'))))
}

async function offline(page: Page, b: Browse, world: StandIn) {
  await openMachine(b, world.base, 'mini')
  await b.until(() => !!document.querySelector('[data-testid=cpu-total]'), { timeout: SHORT_WAIT_MS })
  world.takeOffline('mini')
  await b.until(() => /offline, last seen/.test(document.body.innerText), { timeout: PAGE_POLL_MS + SLACK_MS })
  const grey = await b.run(() => getComputedStyle(document.querySelector('[data-testid=monitor-numbers]') ?? document.body).opacity)
  check('an offline machine says "offline, last seen" and keeps its last numbers greyed', Number(grey) < 1 && (await cpuText(b)) !== '' && !/^0%$/.test(await cpuText(b)))
  await page.setViewport(SIZES.phone)
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
    await b.until(() => !!document.querySelector('[data-testid=cpu-total]'), { timeout: SHORT_WAIT_MS })
    await b.shot(`monitor-studio-${size}.png`, true)
    check(`no sideways scroll at ${size} width`, await b.run(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
  }
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
  await hostileName(b)
  await pageAsksEveryFiveSeconds(world)
  await hiddenTab(b, world)
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
