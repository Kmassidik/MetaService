// Renaming a machine in a real browser against a stand-in Root: the pencil, the window, the rules and the refusals, one request for five quick clicks, a phone-width screen.
// Needs: a built panel (set PANEL_DIST to its folder, or `bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/. No Root, no helper.
// Run: bun e2e/rename.e2e.ts   (SHOTS_DIR=<existing folder> to keep screenshots)
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { startStandIn } from './actions/standin.ts'
import { DESKTOP, renameWorks } from './actions/rename.ts'

const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  await renameWorks(browse(page), standin)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
