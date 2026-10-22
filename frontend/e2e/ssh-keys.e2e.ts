// The SSH keys of a VM in a real browser against a stand-in Root that keeps the keys in memory and applies the parent's rules to a pasted line.
// Needs: a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/. No Root, no helper.
// Run: bun e2e/ssh-keys.e2e.ts   (SHOTS_DIR=<existing folder> to keep screenshots)
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { startStandIn } from './actions/standin.ts'
import { sshKeysDialogWorks } from './actions/ssh.ts'

const DESKTOP = { width: 1280, height: 800 }

const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  await sshKeysDialogWorks(browse(page), standin)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
