// The machine Compute tab in a real browser: managed VMs and existing external services drawn as blocks of one Building, with the machine and GPU memory beside it.
// The stand-in proves read-only discovery, old-helper behavior, the dialog a block opens, one POST per rapid action burst, refresh, busy state and real failures.
// Needs: a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/. No Root, no helper.
// Run: bun e2e/external-services.e2e.ts
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { wait } from './support/net.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { watchWrites } from './actions/confirm.ts'
import { startStandIn } from './actions/standin.ts'

const VMS_TAB = '#/machines/details?id=studio&tab=vms'
const SHORT_WAIT_MS = 8000
const RAPID_CLICKS = 5
const EXTERNAL_SECTION = 'section[aria-labelledby="external-services-title"]'
const BLOCK = '.bv-building .bv-extfloor .bv-ext'
const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })

/** What the dialog of one service holds; the same ids mark its block in the Building, so the dialog's own part is named. */
function rowSelector(id: string): string {
  return `dialog[open] [data-service-id="${id}"]`
}

try {
  const page = await browser.newPage()
  await page.setViewport({ width: 1440, height: 1000 })
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const writes = watchWrites(page)
  const b = browse(page)

  standin.external.available = true
  standin.external.gpu = true
  standin.apps.begin('vm1', 'openclaw')
  standin.apps.finish('vm1')
  standin.apps.failure = 'Hermes install failed in the stand-in'
  standin.apps.begin('vm2', 'hermes')
  standin.apps.finish('vm2')
  await page.goto(`${standin.base}/${VMS_TAB}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector(BLOCK)
  await wait(500)

  check('Compute unifies managed and external nodes without a separate Apps block', await b.run(() =>
    document.querySelector('section[aria-labelledby="managed-vms-title"]') !== null &&
    document.querySelector('section[aria-labelledby="apps-title"]') === null &&
    document.querySelector('section[aria-labelledby="external-services-title"]') === null &&
    document.querySelectorAll('.bv-ext').length === 3
  ))
  check('Apps are badges on their managed Building nodes', await b.run(() => {
    const text = document.querySelector('.bv-tenants')?.textContent ?? ''
    return text.includes('OpenClaw') && text.includes('Hermes') && text.includes('vm1') && text.includes('vm2')
  }))
  check('blocks are one per service with name and runtime, running first', await b.run(() => {
    const blocks = [...document.querySelectorAll('.bv-extfloor .bv-ext')].map((block) => block.textContent ?? '')
    return blocks.length === 3 && blocks[0]?.includes('postgres') === true && blocks[0]?.includes('docker') === true && blocks[1]?.includes('mac-guest') === true && blocks[2]?.includes('build-cache') === true
  }))
  check('stopped, running and unreadable blocks look different', await b.run(() => {
    const tone = (name: string) => [...document.querySelectorAll('.bv-ext')].find((block) => block.textContent?.includes(name))?.className ?? ''
    return tone('postgres').includes('bv-ext-run') && tone('build-cache').includes('bv-ext-stop') && tone('mac-guest').includes('bv-ext-unknown')
  }))
  check('external blocks sit inside the Building, above the floors, with no card and no table', await b.run(() => {
    const floors = [...document.querySelectorAll('.bv-building .bv-floor')]
    const ext = document.querySelector('.bv-extfloor')
    return ext !== null && floors.indexOf(ext) === 2 && document.querySelector('.bv-external') === null &&
      document.querySelector('.runs')?.textContent?.includes('1/3 running · 3 external') === true &&
      document.body.textContent?.includes('Managed compute') === true &&
      document.querySelector('table[aria-label="External services"]') === null &&
      (document.querySelector('[aria-label="External service warnings"]')?.textContent ?? '').includes('One instance could not be inspected.')
  }))
  check('the GPU row says what the card really holds', await b.run(() => document.querySelector('.bv-dark em')?.textContent === 'RTX 5090 · 29.5 GB of 32 GB in use · 2.5 GB free'))
  check('the side card has two charts, machine memory and GPU memory, and names the program', await b.run(() => {
    const side = document.querySelector('.bv-side')
    const gpu = side?.querySelector('.gpu-memory')
    return side?.querySelector('.real-memory') !== null && gpu !== null && gpu?.textContent?.includes('92% used') === true &&
      gpu?.textContent?.includes('29.5 GB of 32 GB') === true && gpu?.textContent?.includes('sglang') === true &&
      gpu?.querySelectorAll('.memory-bar i').length === 3
  }))
  check('real machine memory uses measured used, cache and free colors', await b.run(() =>
    document.querySelector('.bv-side .real-memory .memory-bar') !== null &&
    document.querySelector('.managed-block > .real-memory') === null &&
    document.querySelector('.real-memory .memory-total')?.textContent?.includes('20% used') === true &&
    document.querySelector('.real-memory .memory-total')?.textContent?.includes('20 GB of 100 GB') === true &&
    document.querySelector('.real-memory')?.textContent?.includes('includes VMs, external services and the OS') === true &&
    document.querySelectorAll('.real-memory .memory-bar .used, .real-memory .memory-bar .cached, .real-memory .memory-bar .free').length === 3 &&
    document.querySelector('.bv-occ')?.textContent?.includes('Managed compute') === true
  ))
  check('discovery sends zero writes and one read', writes.count() === 0 && standin.external.discoveries === 1 && standin.external.actions.length === 0, `writes=${writes.count()} reads=${standin.external.discoveries}`)
  await b.shot('machine-workload-blocks.png', true)

  /** Closes any open dialog, then clicks the service's block, which opens its dialog. */
  async function openBlock(id: string): Promise<void> {
    await page.keyboard.press('Escape')
    await wait(150)
    await page.click(`${BLOCK}[data-service-id="${id}"]`)
    await page.waitForSelector(rowSelector(id))
  }

  await b.click('Cards')
  await page.waitForSelector('.external-card')
  await b.shot('machine-vm-cards.png')
  await b.click('Building')

  async function burst(id: string, label: string): Promise<void> {
    await openBlock(id)
    const at = await b.run((selector, wanted) => {
      const button = [...(document.querySelector(selector)?.querySelectorAll('button') ?? [])].find((entry) => entry.textContent?.trim() === wanted)
      if (!button) return null
      button.scrollIntoView({ block: 'center' })
      const box = button.getBoundingClientRect()
      return { x: box.x + box.width / 2, y: box.y + box.height / 2 }
    }, rowSelector(id), label)
    if (!at) throw new Error(`there is no ${label} button for ${id}`)
    await page.mouse.click(at.x, at.y, { count: RAPID_CLICKS })
  }

  standin.external.delayMs = 700
  standin.external.commandDelayMs = 1000
  await openBlock('docker:abc123')
  check('a block opens a dialog with the image, runtime, id and the three actions', await b.run((selector) => {
    const text = document.querySelector(selector)?.textContent ?? ''
    const buttons = [...(document.querySelector(selector)?.querySelectorAll('button') ?? [])].map((button) => button.textContent?.trim())
    return ['postgres:18', 'docker', 'container', 'running', 'docker:abc123'].every((word) => text.includes(word)) && ['Start', 'Stop', 'Restart'].every((label) => buttons.includes(label))
  }, rowSelector('docker:abc123')))
  await b.shot('machine-external-dialog.png')
  await burst('incus:build', 'Start')
  await wait(200)
  check('Start is visibly busy and disables repeated presses', await b.run((selector) => {
    const button = [...(document.querySelector(selector)?.querySelectorAll('button') ?? [])].find((entry) => entry.textContent?.trim() === 'Starting…')
    return button?.disabled === true && button.getAttribute('aria-busy') === 'true' && button.querySelector('.btn-spin') !== null
  }, rowSelector('incus:build')))
  await b.until((selector) => document.querySelector(selector)?.textContent?.includes('running') && ![...(document.querySelector(selector)?.querySelectorAll('button') ?? [])].some((entry) => entry.getAttribute('aria-busy') === 'true'), { timeout: SHORT_WAIT_MS }, rowSelector('incus:build'))
  check('five Start presses send one action and refresh discovery', standin.external.actions.length === 1 && standin.external.actions[0] === 'start incus:build' && standin.external.discoveries === 2, standin.external.actions.join(' | '))

  standin.external.refuseWith = 'Docker is not running'
  await burst('docker:abc123', 'Stop')
  await b.until((selector) => document.querySelector(selector)?.querySelector('.aline.bad')?.textContent?.includes('Docker is not running'), { timeout: SHORT_WAIT_MS }, rowSelector('docker:abc123'))
  check('a real action refusal is shown and the button is free again', await b.run((selector) => {
    const row = document.querySelector(selector)
    const stop = [...(row?.querySelectorAll('button') ?? [])].find((entry) => entry.textContent?.trim() === 'Stop')
    return row?.querySelector('.aline.bad')?.textContent === 'Docker is not running' && stop?.disabled === false
  }, rowSelector('docker:abc123')))
  check('five refused Stop presses send one action and no refresh', standin.external.actions.length === 2 && standin.external.actions[1] === 'stop docker:abc123' && standin.external.discoveries === 2, standin.external.actions.join(' | '))

  standin.external.refuseWith = null
  standin.external.delayMs = 0
  standin.external.commandDelayMs = 0
  await burst('apple:8D6C7F2E', 'Restart')
  await b.until((selector) => document.querySelector(selector)?.textContent?.includes('running'), { timeout: SHORT_WAIT_MS }, rowSelector('apple:8D6C7F2E'))
  check('five Restart presses send one action and refresh the new state', standin.external.actions.length === 3 && standin.external.actions[2] === 'restart apple:8D6C7F2E' && standin.external.discoveries === 3, standin.external.actions.join(' | '))
  check('external actions never create managed VMs or extra Apps', await b.run(() => document.querySelectorAll('.bv-tenants > li').length === 3 && document.querySelectorAll('.bv-ext').length === 3 && document.querySelector('section[aria-labelledby="apps-title"]') === null))

  standin.clearVms('studio')
  await page.reload({ waitUntil: 'networkidle0' })
  await page.waitForSelector(BLOCK)
  check('empty managed compute shows a useful state instead of 0 percent', await b.run(() =>
    document.querySelector('.bv-empty-compute')?.textContent?.includes('No MetaService workloads') === true &&
    document.querySelector('.bv-empty-compute')?.textContent?.includes('0%') === false &&
    document.querySelector('.runs')?.textContent?.includes('0/0 running · 3 external') === true
  ))
  await b.click('Table')
  await page.waitForSelector('.external-row')
  check('the Table view lists the three services as rows, the Docker one with its logo, with no VM empty message', await b.run(() => {
    const rows = [...document.querySelectorAll('.external-row')]
    const docker = rows.find((row) => row.textContent?.includes('postgres'))
    return rows.length === 3 && docker?.querySelector('img.runtime-logo') !== null && rows.filter((row) => row.querySelector('img.runtime-logo') !== null).length === 1 &&
      document.querySelector('.empty') === null && document.querySelector('.external-node') === null
  }))
  await b.shot('machine-external-table.png')
  await b.click('Cards')
  await page.waitForSelector('.external-card')
  check('the Cards view shows the three services as cards, the Docker one with its logo', await b.run(() => {
    const cards = [...document.querySelectorAll('.external-card')]
    return cards.length === 3 && cards.filter((card) => card.querySelector('img.runtime-logo') !== null).length === 1 && cards.some((card) => card.textContent?.includes('postgres:18'))
  }))
  await b.shot('machine-external-cards.png')
  await page.click('.external-card[data-service-id="docker:abc123"] button')
  await page.waitForSelector('dialog[open] [data-service-id="docker:abc123"]')
  check('Details on a card opens the same dialog, with the logo', await b.run(() => document.querySelector('dialog[open] img.runtime-logo') !== null))
  await page.keyboard.press('Escape')
  await b.click('Building')

  standin.reset()
  writes.clear()
  await page.goto('about:blank')
  await page.goto(`${standin.base}/${VMS_TAB}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector('section[aria-labelledby="managed-vms-title"]')
  await wait(500)
  check('an old helper keeps managed VMs and Apps but hides External services', await b.run((selector) =>
    document.querySelector(selector) === null && document.querySelector('.bv-ext') === null && document.querySelector('.gpu-memory') === null && document.querySelector('.bv-tenants') !== null && document.body.textContent?.includes('vm1') === true
  , EXTERNAL_SECTION))
  check('legacy discovery is also read-only and sends no action', writes.count() === 0 && standin.external.discoveries === 1 && standin.external.actions.length === 0, `writes=${writes.count()} reads=${standin.external.discoveries}`)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
