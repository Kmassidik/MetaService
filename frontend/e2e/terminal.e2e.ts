// The web terminal of a VM in a real browser against a real Root and a real Agent (simulated engine, so the shell is /bin/sh on this computer):
// opening it from the VM page, typing, the screen size, Escape and Close, the end of the shell, and Reconnect with a new ticket.
// Needs: the Root and macOS Agent builds, a built panel (`bun run build`), Google Chrome (or CHROME_PATH), and `bun install` in frontend/.
// Run: bun e2e/terminal.e2e.ts
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { firstRun } from './panel/first-run.ts'
import { signInWithAWrongThenTheRightPassword } from './panel/machines.ts'
import { terminalScenario } from './panel/terminal.ts'
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
  await terminalScenario(b, world)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  stopWorld(world)
}
finish()
