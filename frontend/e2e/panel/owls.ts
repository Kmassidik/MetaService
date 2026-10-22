// The owl on the screens that no other scenario reaches: a machine or VM that is not there, the loading screen, and the "could not load" screen with Try again.
import type { HTTPRequest } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import { noSideScroll, owlCachedForAYear, owlShown } from '../support/owls.ts'
import type { Browse } from '../support/page.ts'

const SHORT_WAIT_MS = 10000
const SESSION_ADDRESS = '/api/session'
const POLL_MS = 50
/** What the browser logs for the session request that this scenario cancels on purpose. */
export const CANCELLED_ON_PURPOSE = /net::ERR_FAILED/

export async function notFoundScreens(b: Browse): Promise<void> {
  await b.go('#/machines/details?id=nobody-here')
  await b.until(() => document.body.innerText.includes('No machine with that name'), { timeout: SHORT_WAIT_MS })
  await owlShown(b, 'notFound', 'a machine that does not exist')
  await owlCachedForAYear(b, 'notFound')
  check('the missing machine keeps its sentence and its way back', (await b.text()).includes('← Machines'))
  await b.shot('owl-machine-not-found.png')
  await b.go('#/machines/details?id=dgx-spark&vm=nope')
  await b.until(() => document.body.innerText.includes('VM not found'), { timeout: SHORT_WAIT_MS })
  await owlShown(b, 'notFound', 'a VM that does not exist')
  await noSideScroll(b, 'the VM not found screen')
}

/** Holds the page's first session request so the loading screen stays up while it is looked at, then cancels it so the error screen shows. Leaves the page working again. */
export async function loadingThenErrorScreens(b: Browse): Promise<void> {
  let holding = true
  const hold: { request: HTTPRequest | null } = { request: null }
  const answer = (request: HTTPRequest): void => {
    if (!holding || !request.url().endsWith(SESSION_ADDRESS)) return void request.continue()
    hold.request = request
  }
  await b.page.setRequestInterception(true)
  b.page.on('request', answer)
  void b.page.reload()
  while (!hold.request) await wait(POLL_MS)
  await owlShown(b, 'loading', 'the loading screen')
  await noSideScroll(b, 'the loading screen')
  await b.shot('owl-loading.png')
  holding = false
  await hold.request.abort()
  await b.until(() => document.body.innerText.includes('Try again'), { timeout: SHORT_WAIT_MS })
  await owlShown(b, 'notFound', 'the could-not-load screen')
  check('the could-not-load screen keeps its sentence and Try again', /Cannot reach the Root\./.test(await b.text()) && !(await b.isDisabled('Try again')))
  await noSideScroll(b, 'the could-not-load screen')
  await b.shot('owl-error.png')
  await b.click('Try again')
  await b.until(() => document.body.innerText.includes('VM not found'), { timeout: SHORT_WAIT_MS })
  b.page.off('request', answer)
  await b.page.setRequestInterception(false)
}
