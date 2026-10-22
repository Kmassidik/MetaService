// The Start, Stop and Delete buttons, the chat bundle buttons and the Ruvio switch in a real browser against a stand-in Root that answers slowly, refuses, or stays silent on command (the real Root is too quick to press twice).
// Needs: a built panel (`bun run build`), Google Chrome (or CHROME_PATH), `bun install` in frontend/. No Root, no helper.
// Run: bun e2e/actions.e2e.ts
import puppeteer from 'puppeteer-core'
import { check, finish } from './support/check.ts'
import { browse } from './support/page.ts'
import { chromePath } from './support/paths.ts'
import { deleteRefusalKeepsTheDialog, deleteStaysOpenWhileWorking, keysSendOneRequest, onAPhone, refusalShowsNextToTheButton, silentRootFreesTheButton, startAndStopSendOneRequest, successLineGoesAway, watchVmRequests } from './actions/guard.ts'
import * as bundles from './actions/bundles.ts'
import { everyDestructiveButtonAsksFirst, watchWrites } from './actions/confirm.ts'
import { startStandIn } from './actions/standin.ts'

const DESKTOP = { width: 1280, height: 800 }

const standin = await startStandIn()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const watch = watchVmRequests(page)
  const b = browse(page)

  await startAndStopSendOneRequest(b, standin, watch)
  await keysSendOneRequest(b, standin, watch)
  await refusalShowsNextToTheButton(b, standin, watch)
  await successLineGoesAway(b, standin)
  await deleteStaysOpenWhileWorking(b, standin, watch)
  await deleteRefusalKeepsTheDialog(b, standin)
  await onAPhone(b, standin)
  await everyDestructiveButtonAsksFirst(b, standin, watchWrites(page))
  const bundleWatch = bundles.watchBundleRequests(page)
  await bundles.fiveClicksSendOneRequest(b, standin, bundleWatch)
  await bundles.keysSendOneRequest(b, standin, bundleWatch)
  await bundles.refusalShowsNextToTheControl(b, standin, bundleWatch)
  await bundles.switchSendsOneRequest(b, standin, bundleWatch)
  await bundles.switchKeysSendOneRequest(b, standin, bundleWatch)
  await bundles.switchGoesBackWhenRefused(b, standin, bundleWatch)
  await bundles.successLineGoesAway(b, standin)
  await bundles.onAPhone(b, standin)
  await silentRootFreesTheButton(b, standin, watch)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  await browser.close()
  standin.close()
}
finish()
