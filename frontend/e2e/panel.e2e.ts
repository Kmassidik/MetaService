// End-to-end test of the panel in a real browser against a real Root: first run, sign in, Overview, Machines (and that Add a machine has one way in: Find machines),
// a machine's page and its VMs, the chat bundle, the AI provider, Find machines, and a phone.
// Needs: the Root build (`swift build` in control-plane/arm64), the macOS Agent build, a built panel (`bun run build`), Google Chrome (or CHROME_PATH), and `bun install` in frontend/.
// Run: bun e2e/panel.e2e.ts
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { noSideScroll, owlShown } from './support/owls.ts'
import { chromePath } from './support/paths.ts'
import { browse } from './support/page.ts'
import { brainScenario } from './panel/brain.ts'
import { bundleScenario } from './panel/bundles.ts'
import { firstRun } from './panel/first-run.ts'
import { hostileTextIsShownAsText, machinesList, overviewAndSidebar, removeAMachine, signInWithAWrongThenTheRightPassword } from './panel/machines.ts'
import { CANCELLED_ON_PURPOSE, loadingThenErrorScreens, notFoundScreens } from './panel/owls.ts'
import { scanScenario } from './panel/scan.ts'
import { seed, startWorld, stopWorld } from './panel/world.ts'
import { workloadScenario } from './panel/workloads.ts'

const DESKTOP = { width: 1280, height: 800 }
const PHONE = { width: 390, height: 844 }
const SIGN_OUT_WAIT_MS = 10000

const world = await startWorld()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|502)/.test(message.text()) && !CANCELLED_ON_PURPOSE.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { window.violation = event.violatedDirective }))
  const b = browse(page)

  await firstRun(b, world)
  await seed(world)
  await signInWithAWrongThenTheRightPassword(b, world)
  await overviewAndSidebar(b)
  await machinesList(b)
  await hostileTextIsShownAsText(b)
  await removeAMachine(b)
  await workloadScenario(b, world)
  await bundleScenario(b, world)
  await brainScenario(b, world)
  await scanScenario(b)
  await notFoundScreens(b)
  await loadingThenErrorScreens(b)

  await page.setViewport(PHONE)
  await page.reload({ waitUntil: 'networkidle0' })
  check('no sideways scrolling on a phone', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await notFoundScreens(b)
  await b.go('#/')
  await b.click('Sign out')
  await b.until(() => /sign in to manage/i.test(document.body.innerText), { timeout: SIGN_OUT_WAIT_MS })
  check('signing out returns to the sign-in page and shows nothing', !(await b.text()).includes('dgx-spark'))
  await owlShown(b, 'hero', 'the sign-in page on a phone')
  await noSideScroll(b, 'the sign-in page on a phone')
  await b.shot('owl-login-phone.png')
  check('no script errors and no policy violations', errors.length === 0 && (await b.run(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  stopWorld(world)
}
finish()
