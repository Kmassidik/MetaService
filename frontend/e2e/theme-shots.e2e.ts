// Pictures of the real panel with its palette (src/palette.css), page by page, at desktop and phone width.
// A regression picture tool, not a test: it is not part of the `e2e` script.
// Needs: the Root build and the macOS helper build (`swift build`), a built panel (`bun run build`), Google Chrome (or CHROME_PATH), /usr/sbin/sshd, and `bun install` in frontend/.
// Run: SHOTS_DIR=<dir> bun e2e/theme-shots.e2e.ts   (pictures: <page>-<desktop|phone>.png)
import { mkdirSync } from 'node:fs'
import puppeteer from 'puppeteer-core'
import { createAdmin } from './support/admin.ts'
import { chromePath, panelDist, screenshotDir } from './support/paths.ts'
import { browse } from './support/page.ts'
import { scanSettings, startRoot } from './support/root.ts'
import { startSshd } from './support/sshd.ts'
import { startStandIn } from './monitor/stand-in.ts'
import { resendHeartbeats, stopWorld } from './panel/world.ts'
import type { PageId } from '../src/lib/shotNames.ts'
import { capture } from './themes/capture.ts'
import { seedFleet, worldAround } from './themes/fleet.ts'
import { allVmsWithCreate, addMachineCheck, livePage, loginPage, machinesPage, offlineMachine, overviewPage, signInAsAdmin, vmsTab } from './themes/steps.ts'

const SETUP_TOKEN = 'e2e-setup-token-0123456789abcdef'

if (screenshotDir === undefined) throw new Error('set SHOTS_DIR to the folder for the pictures')
const dir = screenshotDir
mkdirSync(dir, { recursive: true })

const scan = scanSettings()
const sshd = await startSshd()
const standIn = startStandIn(panelDist)
const root = await startRoot({
  envLines: [`ROOT_SETUP_TOKEN=${SETUP_TOKEN}`, ...scan.envLines],
  args: ['--remote-allow-loopback', 'yes', '--remote-engine', 'simulated', '--remote-tries', '30'],
  processEnv: scan.processEnv,
})
const world = worldAround(root)
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  await createAdmin(root.base, SETUP_TOKEN)
  await seedFleet(world)
  const page = await browser.newPage()
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const b = browse(page)
  const picture = async (name: PageId) => {
    await resendHeartbeats(world)
    await capture(page, dir, name)
    console.log(`pictures of ${name}`)
  }

  await loginPage(b, root.base)
  await picture('login')
  await signInAsAdmin(b)
  await overviewPage(b)
  await picture('overview')
  await machinesPage(b)
  await picture('machines')
  await livePage(b, standIn.base)
  await picture('live')
  await vmsTab(b, root.base)
  await picture('vms-tab')
  await allVmsWithCreate(b)
  await picture('all-vms-create')
  await offlineMachine(b, root.base)
  await picture('offline-machine')
  const stopAnswering = await addMachineCheck(b, sshd.port, sshd.fingerprint)
  await picture('add-machine-check')
  await stopAnswering()
} finally {
  await browser.close()
  standIn.stop()
  sshd.child.kill()
  stopWorld(world)
}
