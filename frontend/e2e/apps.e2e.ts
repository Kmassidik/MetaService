// OpenClaw and Hermes installed inside a VM after it starts, in a real browser against a stand-in Root: the Install on top menu, the create request, the chip in the VM lists, and the Software block of the VM page.
// Needs: a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/. No Root, no helper.
// Run: bun e2e/apps.e2e.ts   (SHOTS_DIR=<existing folder> to keep screenshots)
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { startStandIn } from './actions/standin.ts'
import { recordCreateBodies } from './vms/images.ts'
import { createSendsTheBundle, DESKTOP, greyedForAnOldHelper, selectableWhenReady } from './apps/catalog.ts'
import { chipFollowsTheInstall, failedChipShowsTheMessage, noChipWithoutAnApp } from './apps/lists.ts'
import { failedOnAPhoneAndStoppedVm, failedShowsMessageLogAndTryAgain, noBlockWithoutAnApp, pollsOnlyWhileInstalling, stopsWhenThePageCloses } from './apps/software.ts'

const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const bodies = recordCreateBodies(page)
  const b = browse(page)
  await selectableWhenReady(b, standin)
  await greyedForAnOldHelper(b, standin)
  await createSendsTheBundle(b, standin, bodies)
  await chipFollowsTheInstall(b, standin)
  await failedChipShowsTheMessage(b, standin)
  await noChipWithoutAnApp(b, standin)
  await pollsOnlyWhileInstalling(b, standin)
  await stopsWhenThePageCloses(b, standin)
  await failedShowsMessageLogAndTryAgain(b, standin)
  await failedOnAPhoneAndStoppedVm(b, standin)
  await noBlockWithoutAnApp(b, standin)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
