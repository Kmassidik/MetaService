// The machine page in a real browser against a stand-in parent: Overview, Environment with the real mac-studio record, Ruvio on and off,
// Save with the parent's refusal shown, a parent with no chat built, and pictures at desktop and phone width in light and dark.
// Needs: a built panel (set PANEL_DIST to its folder; `bunx vite build --outDir <dir>`), Google Chrome (or CHROME_PATH), `bun install` in frontend/.
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/machine-page.e2e.ts
import puppeteer, { type Page } from 'puppeteer-core'
import { startFakeParent } from './machine/fake-parent.ts'
import { SHORT_WAIT_MS, changeField, expectNoSideScroll, fieldError, fieldValue, openMachine, openTab, pressSwitch, saveDisabled, softwareValue, switchState, untilSwitch } from './machine/steps.ts'
import { check, finish } from './support/check.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, panelDist } from './support/paths.ts'

const SIZES = { desktop: { width: 1280, height: 900 }, phone: { width: 390, height: 844 } }
const SCHEMES = ['light', 'dark'] as const
const NOT_REPORTED = 'not reported'

async function overview(b: Browse) {
  const shown = await b.text()
  check('the tabs are Overview, Environment, Deployments, Activity', await b.run(() => [...document.querySelectorAll('[role=tab]')].map((tab) => tab.textContent?.trim().replace(/\s*\(\d+\)$/, '')).join('|') === 'Overview|Environment|Deployments|Activity'))
  check('the Overview has the facts of the real mac-studio record', /ID\s*mac-studio/i.test(shown) && /CPU\s*14 cores/i.test(shown) && /of 36 GB/.test(shown) && /of 494 GB/.test(shown) && /System\s*macOS · Apple Silicon/i.test(shown), shown.slice(0, 600))
  check('the Overview says what the machine can run', shown.includes('Can run: VMs and containers · GPU in a VM: no · GPU in a container: no'))
  check('the Overview no longer shows a profile or the old set-up block', !/Profile/.test(shown) && !/How this machine was set up/.test(shown))
  check('the Overview uses only the words of the model: no "agent", "node" or "host"', !/\b(agent|node|host|workload)\b/i.test(shown))
}

async function software(b: Browse) {
  check('a helper version nobody reported says "not reported"', (await softwareValue(b, 'Helper version')) === NOT_REPORTED)
  check('the engine says what it is and that it is ready', (await softwareValue(b, 'Engine')) === 'Apple container, ready')
  check('the helper folder and port are shown', (await softwareValue(b, 'Helper folder')) === '~/metaservice-box' && (await softwareValue(b, 'Helper port')) === '8447')
  check('the tunnel state is shown', ((await softwareValue(b, 'Tunnel')) ?? '').startsWith('SSH tunnel · connected'))
}

async function ruvioOnAndOff(b: Browse, commands: string[]) {
  const first = await switchState(b)
  check('Ruvio is off by default and the switch can be pressed', first?.on === false && first.disabled === false)
  check('there is no Open chat while Ruvio is off', !(await b.text()).includes('Open chat'))
  await pressSwitch(b)
  await b.until(() => /turning on/.test(document.body.innerText), { timeout: SHORT_WAIT_MS })
  check('while it turns on the switch waits', (await switchState(b))?.disabled === true)
  await untilSwitch(b, true)
  check('Ruvio on: the parent was asked to install, the version shows, Open chat appears', commands.join() === 'install' && (await b.text()).includes('Open chat') && /Installed version\s*0\.4\.0/i.test(await b.text()))
  await pressSwitch(b)
  await untilSwitch(b, false)
  check('Ruvio off: the parent was asked to uninstall and Open chat is gone', commands.join() === 'install,uninstall' && !(await b.text()).includes('Open chat'))
  check('the page says chat data stays when Ruvio is off', (await b.text()).includes('keeps its chat data'))
}

async function saving(b: Browse, patches: unknown[]) {
  check('Save is off while nothing changed', await saveDisabled(b))
  await changeField(b, 'vmCpu', '65')
  check('a CPU above the parent\'s limit is refused in the page, with its range', ((await fieldError(b, 'vmCpu')) ?? '').includes('between 1 and 64') && (await saveDisabled(b)))
  await changeField(b, 'vmCpu', '4')
  await changeField(b, 'vmRamMb', '4096')
  await changeField(b, 'ramReserveMb', '5000')
  await changeField(b, 'ramAllowanceMb', '4096')
  check('a reserve that is not below the allowance is refused in the page', ((await fieldError(b, 'ramReserveMb')) ?? '').includes('must be smaller') && (await saveDisabled(b)))
  await changeField(b, 'ramReserveMb', '2048')
  await changeField(b, 'subdomain', 'Bad Name!')
  check('a bad name on the internet is refused in the page', ((await fieldError(b, 'subdomain')) ?? '') !== '' && (await saveDisabled(b)))
  await changeField(b, 'subdomain', 'studio')
  await changeField(b, 'labels', 'lab, gpu')
  await b.shot('machine-environment-edited-desktop-light.png', true)
  await b.click('Save')
  await b.until(() => /Saved\./.test(document.body.innerText), { timeout: SHORT_WAIT_MS })
  check('Save sends only the fields that changed, with the parent\'s names', JSON.stringify(patches[0]) === JSON.stringify({ labels: ['lab', 'gpu'], ram_reserve_mb: 2048, ram_allowance_mb: 4096, vm_cpu: 4, vm_ram_mb: 4096, subdomain: 'studio' }), JSON.stringify(patches[0]))
  check('after Save the page says the changes apply to new VMs only', (await b.text()).includes('The changes apply to new VMs only.'))
  await openTab(b, 'Overview')
  await openTab(b, 'Environment')
  check('the saved values are still there after leaving and coming back', (await fieldValue(b, 'vmCpu')) === '4' && (await fieldValue(b, 'subdomain')) === 'studio' && (await fieldValue(b, 'labels')) === 'lab, gpu')
  await changeField(b, 'name', 'mac-mini')
  await b.click('Save')
  await b.until(() => !!document.querySelector('form [role=alert]'), { timeout: SHORT_WAIT_MS })
  check('the parent\'s refusal text is shown when it refuses', (await b.text()).includes('another machine already has that name'))
  check('the form stays as typed after a refusal, ready to fix', (await fieldValue(b, 'name')) === 'mac-mini' && !(await saveDisabled(b)))
}

async function pictures(page: Page, b: Browse, base: string) {
  for (const [size, viewport] of Object.entries(SIZES)) {
    for (const scheme of SCHEMES) {
      await page.setViewport(viewport)
      await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: scheme }])
      await openMachine(b, base, 'mac-studio')
      await openTab(b, 'Overview')
      await b.shot(`machine-overview-${size}-${scheme}.png`, true)
      await expectNoSideScroll(b, `Overview, ${size}, ${scheme}`)
      await openTab(b, 'Environment')
      await b.until(() => !!document.querySelector('section[aria-label=Software]'), { timeout: SHORT_WAIT_MS })
      await b.shot(`machine-environment-${size}-${scheme}.png`, true)
      await expectNoSideScroll(b, `Environment, ${size}, ${scheme}`)
    }
  }
}

async function noChatBuilt(page: Page, b: Browse, base: string) {
  await page.setViewport(SIZES.desktop)
  await openMachine(b, base, 'mac-studio')
  await openTab(b, 'Environment')
  await b.until(() => !!document.querySelector('button[role=switch]'), { timeout: SHORT_WAIT_MS })
  const state = await switchState(b)
  check('with no chat built the Ruvio switch is off and disabled', state?.on === false && state.disabled === true)
  check('it says "no chat is built on the parent"', (await b.text()).includes('no chat is built on the parent'))
  await b.shot('machine-environment-no-chat-desktop-light.png', true)
}

const errors: string[] = []
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
const parent = startFakeParent({ chatsBuilt: 1, dist: panelDist })
const bare = startFakeParent({ chatsBuilt: 0, dist: panelDist })
try {
  const page = await browser.newPage()
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (403|409)/.test(message.text()) && errors.push(message.text()))
  const b = browse(page)
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await openMachine(b, parent.base, 'mac-studio')
  await overview(b)
  await openTab(b, 'Environment')
  await b.until(() => !!document.querySelector('button[role=switch]'), { timeout: SHORT_WAIT_MS })
  await software(b)
  await ruvioOnAndOff(b, parent.commands)
  await pictures(page, b, parent.base)
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  await openMachine(b, parent.base, 'mac-studio')
  await openTab(b, 'Environment')
  await b.until(() => !!document.querySelector('button[role=switch]'), { timeout: SHORT_WAIT_MS })
  await saving(b, parent.patches)
  await noChatBuilt(page, b, bare.base)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  parent.stop()
  bare.stop()
}
finish()
