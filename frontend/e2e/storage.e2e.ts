// The Storage tab in a real browser against a stand-in parent: the first scan starts by itself, the map is drawn like disktree (areas in proportion,
// the hidden space as its own tile), folders open and the trail and Escape lead back, "Worth a look" opens what it names, Rescan asks once,
// a folder name with markup stays text, an older helper gets a plain note, and pictures at desktop and phone width.
// Needs: a built panel (set PANEL_DIST to its folder; `bunx vite build --outDir <dir>`), Google Chrome (or CHROME_PATH), `bun install` in frontend/.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/storage.e2e.ts
import puppeteer from 'puppeteer-core'
import { SHORT_WAIT_MS, expectNoSideScroll, openTab } from './machine/steps.ts'
import { startFakeParent } from './storage/fake-parent.ts'
import { HIDDEN_BYTES, HOSTILE_FOLDER, sparkMap } from './storage/sparkMap.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const DESKTOP = { width: 1440, height: 1000 }
const PHONE = { width: 400, height: 844 }
const SCAN_WAIT_MS = 15000
/** How far a tile's share of the map may be from its share of the bytes (borders and rounding). */
const AREA_SLACK = 0.02

const tileNames = (b: Browse) => b.run(() => [...document.querySelectorAll<HTMLElement>('.mosaic .tile')].map((tile) => tile.querySelector('.nm')?.textContent ?? ''))
const trailText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('nav.trail')?.innerText.replace(/\s+/g, ' ').trim() ?? '')
const selectionTitle = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('.st-side .sel .title')?.innerText.trim() ?? '')
/** Opens a machine's page by its id and waits for its heading (the stand-in's spark is called "dgx spark"). */
async function openMachine(b: Browse, base: string, id: string): Promise<void> {
  await b.page.goto(`${base}/#/machines/details?id=${id}`, { waitUntil: 'networkidle0' })
  await b.until(() => !!document.querySelector('.phead h1')?.textContent, { timeout: SHORT_WAIT_MS })
}

const untilMap = (b: Browse) => b.until(() => document.querySelectorAll('.mosaic .tile').length > 5, { timeout: SCAN_WAIT_MS })

async function pressTile(b: Browse, name: string): Promise<void> {
  const index = await b.run((wanted) => [...document.querySelectorAll<HTMLElement>('.mosaic .tile')].findIndex((tile) => tile.querySelector('.nm')?.textContent === wanted), name)
  const tile = (await b.page.$$('.mosaic .tile'))[index]
  if (index < 0 || !tile) throw new Error(`no tile "${name}"`)
  // Near the top-left corner, on the name: the middle of an open folder is covered by what it holds.
  await tile.click({ offset: { x: 6, y: 5 } })
}

async function firstScan(b: Browse, base: string, scans: () => number) {
  await openMachine(b, base, 'spark-20ec')
  await openTab(b, 'Storage')
  await b.until(() => document.body.innerText.includes('Mapping this disk for the first time'), { timeout: SHORT_WAIT_MS })
  check('a machine never scanned starts its first scan by itself, once', scans() === 1)
  await b.shot('storage-first-scan-desktop.png')
  await untilMap(b)
  check('the scan ends in a map without a reload', (await b.text()).includes('scanned'))
  check('the tab is named Storage and sits between VMs and Environment', (await b.run(() => [...document.querySelectorAll('[role=tab]')].map((tab) => tab.textContent?.trim().replace(/\s*\(\d+\)$/, '')).join('|'))) === 'Live|VMs|Storage|Environment|Activity')
}

async function drawnLikeDisktree(b: Browse) {
  const names = await tileNames(b)
  check('the top level shows home, var, usr and the swap file', ['home', 'var', 'usr', 'swap.img'].every((name) => names.includes(name)), names.slice(0, 12).join(', '))
  check('the space the helper could not read is a tile of its own', names.includes('Not readable by the helper'))
  check('folders are opened three levels deep', names.includes('ops') && names.includes('.cache'))
  const shares = await b.run(() => {
    const mosaic = document.querySelector<HTMLElement>('.mosaic')?.getBoundingClientRect()
    const tile = (name: string) => [...document.querySelectorAll<HTMLElement>('.mosaic .tile')].find((one) => one.querySelector('.nm')?.textContent === name)?.getBoundingClientRect()
    const area = (rect: DOMRect | undefined) => (rect ? rect.width * rect.height : 0)
    return { home: area(tile('home')) / area(mosaic), hidden: area(tile('Not readable by the helper')) / area(mosaic) }
  })
  const map = sparkMap(new Date(), 1)
  const top = (name: string) => Number(map.nodes.find((node) => node.parent === 0 && node.name === name)?.bytes ?? 0)
  check('home\'s share of the map is its share of the used space', Math.abs(shares.home - top('home') / map.disk.used_bytes) < AREA_SLACK, String(shares.home))
  check('the hidden tile\'s share is the hidden 38 GiB\'s share', Math.abs(shares.hidden - HIDDEN_BYTES / map.disk.used_bytes) < AREA_SLACK, String(shares.hidden))
  check('the colours are explained in a legend', (await b.text()).includes('VMs & containers') && (await b.text()).includes('Could be had back'))
  check('reclaimable folders are hatched', await b.run(() => !!document.querySelector('.mosaic .tile.hatch')))
}

async function openAndBack(b: Browse) {
  await pressTile(b, 'var')
  await b.until(() => document.querySelector('nav.trail')?.textContent?.includes('var'), { timeout: SHORT_WAIT_MS })
  check('pressing a folder opens it and the trail says where you are', (await trailText(b)) === '/ › var')
  check('inside var, incus is drawn as VMs & containers', await b.run(() => [...document.querySelectorAll<HTMLElement>('.mosaic .tile.k-vms')].some((tile) => tile.querySelector('.nm')?.textContent === 'incus')))
  check('the hidden tile is only at the top', !(await tileNames(b)).includes('Not readable by the helper'))
  await b.page.focus('.st-side button.row')
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('nav.trail')?.textContent?.trim() === '/', { timeout: SHORT_WAIT_MS })
  check('Escape goes back up a level', (await trailText(b)) === '/')
  await pressTile(b, 'swap.img')
  check('pressing a file selects it and the column describes it', (await selectionTitle(b)) === 'swap.img')
  check('the column gives the full path', (await b.text()).includes('/swap.img'))
}

async function worthALook(b: Browse) {
  const first = await b.run(() => document.querySelector<HTMLElement>('.st-side .row.two .nm')?.textContent ?? '')
  check('"Worth a look" starts with the biggest space that could be had back (the cache)', first === '.cache', first)
  await b.run(() => document.querySelector<HTMLElement>('.st-side .row.two')?.click())
  await b.until(() => document.querySelector('nav.trail')?.textContent?.includes('.cache'), { timeout: SHORT_WAIT_MS })
  check('pressing it opens that folder', (await trailText(b)).endsWith('.cache'))
  await b.run(() => document.querySelector<HTMLElement>('nav.trail button')?.click())
  await b.until(() => document.querySelector('nav.trail')?.textContent?.trim() === '/', { timeout: SHORT_WAIT_MS })
}

async function markupStaysText(b: Browse) {
  await b.go('#/machines/details?id=spark-20ec&tab=storage')
  await untilMap(b)
  for (const name of ['home', 'ops', 'projects']) {
    await pressTile(b, name)
    await b.until((wanted) => document.querySelector('nav.trail')?.textContent?.includes(wanted), { timeout: SHORT_WAIT_MS }, name)
  }
  check('a folder named with markup is shown as its text', (await tileNames(b)).includes(HOSTILE_FOLDER))
  check('and no image was made from it', await b.run(() => document.querySelectorAll('.mosaic img').length === 0))
}

async function rescan(b: Browse, scans: () => number) {
  const before = scans()
  await b.click('Rescan')
  await b.until(() => [...document.querySelectorAll('button')].some((button) => button.textContent?.trim() === 'Scanning…'), { timeout: SHORT_WAIT_MS })
  check('Rescan asks the parent once and says it is scanning', scans() === before + 1)
  check('the last map stays on screen while the new scan runs', await b.run(() => document.querySelectorAll('.mosaic .tile').length > 5))
  await b.until(() => [...document.querySelectorAll('button')].some((button) => button.textContent?.trim() === 'Rescan'), { timeout: SCAN_WAIT_MS })
  check('the button comes back when the scan ends', true)
}

async function olderHelper(b: Browse) {
  await b.go('#/machines/details?id=mac-studio&tab=storage')
  await b.until(() => document.body.innerText.includes('cannot map its disk yet'), { timeout: SHORT_WAIT_MS })
  check('a helper without the storage route gets a plain note to update it', (await b.text()).includes('Update the helper on the Environment tab'))
}

const errors: string[] = []
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const parent = startFakeParent(panelDist)
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && errors.push(message.text()))
  page.on('dialog', (dialog) => {
    errors.push(`a dialog opened: ${dialog.message()}`)
    void dialog.dismiss()
  })
  const b = browse(page)
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await firstScan(b, parent.base, parent.scans)
  await b.shot('storage-desktop.png')
  await drawnLikeDisktree(b)
  await openAndBack(b)
  await worthALook(b)
  await markupStaysText(b)
  await b.shot('storage-folder-desktop.png')
  await b.go('#/machines/details?id=spark-20ec&tab=storage')
  await untilMap(b)
  await rescan(b, parent.scans)
  await page.setViewport(PHONE)
  await b.go('#/machines/details?id=spark-20ec&tab=storage')
  await untilMap(b)
  await expectNoSideScroll(b, 'Storage at phone width')
  await b.shot('storage-phone.png', true)
  await page.setViewport(DESKTOP)
  await olderHelper(b)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.stop()
}
finish()
