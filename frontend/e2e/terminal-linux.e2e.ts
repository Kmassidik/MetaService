// The web terminal on Linux machines in a real browser against a real Root and the Fake Agent (agent/fake, a /bin/sh console): a container on a machine whose helper
// says `terminal` opens and shows its echo; one whose helper does not say it is off with "Update the helper to use the terminal"; a Linux VM says "Containers only for now".
// Needs: the Root build, a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/, and FAKE_PYTHON (`nix develop --command which python3`).
// Run: bun e2e/terminal-linux.e2e.ts
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { firstRun } from './panel/first-run.ts'
import { signInWithAWrongThenTheRightPassword } from './panel/machines.ts'
import { terminalLinuxScenario } from './panel/terminal-linux.ts'
import { seed, startWorld, stopWorld } from './panel/world.ts'

const DESKTOP = { width: 1280, height: 800 }

const world = await startWorld()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (401|403|409|502)|WebSocket/.test(message.text()) && errors.push(message.text()))
  const b = browse(page)

  await firstRun(b, world)
  await seed(world)
  await signInWithAWrongThenTheRightPassword(b, world)
  await terminalLinuxScenario(b, world)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  stopWorld(world)
}
finish()
