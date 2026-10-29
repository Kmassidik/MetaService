// The machine VMs tab's three blocks in a real browser: managed VMs, Apps and existing external services.
// The stand-in proves read-only discovery, old-helper behavior, one POST per rapid action burst, refresh, busy state and real failures.
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
const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })

function rowSelector(id: string): string {
  return `[data-service-id="${id}"]`
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
  standin.apps.begin('vm1', 'openclaw')
  standin.apps.finish('vm1')
  standin.apps.failure = 'Hermes install failed in the stand-in'
  standin.apps.begin('vm2', 'hermes')
  standin.apps.finish('vm2')
  await page.goto(`${standin.base}/${VMS_TAB}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector(`${EXTERNAL_SECTION} .external-node`)
  await wait(500)

  check('Compute unifies managed and external nodes without a separate Apps block', await b.run(() =>
    document.querySelector('section[aria-labelledby="managed-vms-title"]') !== null &&
    document.querySelector('section[aria-labelledby="apps-title"]') === null &&
    document.querySelector('section[aria-labelledby="external-services-title"]') !== null &&
    document.querySelectorAll('.external-node').length === 3
  ))
  check('Apps are badges on their managed Building nodes', await b.run(() => {
    const text = document.querySelector('.bv-tenants')?.textContent ?? ''
    return text.includes('OpenClaw') && text.includes('Hermes') && text.includes('vm1') && text.includes('vm2')
  }))
  check('external rows show name, runtime, kind, state, image and warnings', await b.run(() => {
    const table = document.querySelector('section[aria-labelledby="external-services-title"]')?.textContent ?? ''
    const warning = document.querySelector('[aria-label="External service warnings"]')?.textContent ?? ''
    return ['postgres', 'docker', 'container', 'running', 'postgres:18', 'build-cache', 'incus', 'stopped', 'mac-guest', 'apple', 'vm', 'unknown'].every((text) => table.includes(text)) && warning.includes('One instance could not be inspected.')
  }))
  check('external nodes are inside the Building with separate counts', await b.run(() =>
    document.querySelectorAll('.bv-building .bv-external .external-node').length === 3 &&
    document.querySelector('section[aria-labelledby="external-services-title"]')?.textContent?.includes('3 managed · 3 external · 1 external running') === true &&
    document.body.textContent?.includes('Managed compute') === true &&
    document.querySelector('table[aria-label="External services"]') === null
  ))
  check('real machine memory uses measured used, cache and free colors', await b.run(() =>
    document.querySelector('.real-memory .memory-total')?.textContent?.includes('20% used') === true &&
    document.querySelector('.real-memory .memory-total')?.textContent?.includes('20 GB of 100 GB') === true &&
    document.querySelector('.real-memory')?.textContent?.includes('includes VMs, external services and the OS') === true &&
    document.querySelectorAll('.real-memory .memory-bar .used, .real-memory .memory-bar .cached, .real-memory .memory-bar .free').length === 3 &&
    document.querySelector('.bv-occ')?.textContent?.includes('Managed compute') === true
  ))
  check('discovery sends zero writes and one read', writes.count() === 0 && standin.external.discoveries === 1 && standin.external.actions.length === 0, `writes=${writes.count()} reads=${standin.external.discoveries}`)
  await b.shot('machine-workload-blocks.png', true)

  async function burst(id: string, label: string): Promise<void> {
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
  check('external actions never create managed VMs or extra Apps', await b.run(() => document.querySelectorAll('.bv-tenants > li').length === 3 && document.querySelectorAll('.external-node').length === 3 && document.querySelector('section[aria-labelledby="apps-title"]') === null))

  standin.clearVms('studio')
  await page.reload({ waitUntil: 'networkidle0' })
  await page.waitForSelector(`${EXTERNAL_SECTION} .external-node`)
  check('empty managed compute shows a useful state instead of 0 percent', await b.run(() =>
    document.querySelector('.bv-empty-compute')?.textContent?.includes('No MetaService workloads') === true &&
    document.querySelector('.bv-empty-compute')?.textContent?.includes('0%') === false &&
    document.querySelector('section[aria-labelledby="external-services-title"]')?.textContent?.includes('0 managed · 3 external') === true
  ))

  standin.reset()
  writes.clear()
  await page.goto('about:blank')
  await page.goto(`${standin.base}/${VMS_TAB}`, { waitUntil: 'networkidle0' })
  await page.waitForSelector('section[aria-labelledby="managed-vms-title"]')
  await wait(500)
  check('an old helper keeps managed VMs and Apps but hides External services', await b.run((selector) =>
    document.querySelector(selector) === null && document.querySelector('.bv-tenants') !== null && document.body.textContent?.includes('vm1') === true
  , EXTERNAL_SECTION))
  check('legacy discovery is also read-only and sends no action', writes.count() === 0 && standin.external.discoveries === 1 && standin.external.actions.length === 0, `writes=${writes.count()} reads=${standin.external.discoveries}`)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
