// The Page not found screen: an address the panel does not know, a hostile one, and the way back.
import { check } from '../support/check.ts'
import { noSideScroll, owlShown } from '../support/owls.ts'
import type { Browse } from '../support/page.ts'

const SHORT_WAIT_MS = 10000
const UNKNOWN_ADDRESS = '/healthsasdfasdf'
const HOSTILE_ADDRESS = '/<img src=x onerror=alert(1)>'

const heading = () => document.querySelector('main h1')?.textContent
const shownAddress = () => document.querySelector('main .empty code')?.textContent
const activeInSidebar = () => [...document.querySelectorAll('aside.side nav [aria-current], aside.side nav .on, aside.side nav .here')].map((element) => element.outerHTML.slice(0, 80))

const waitForHeading = (b: Browse, title: string) => b.until((wanted) => document.querySelector('main h1')?.textContent === wanted, { timeout: SHORT_WAIT_MS }, title)

/** Visits an unknown address and checks the screen, the way back, and that a real address with a trailing slash still works. `shotName` is the screenshot to keep. */
export async function pageNotFoundScreen(b: Browse, shotName: `${string}.png`): Promise<void> {
  await b.go(`#${UNKNOWN_ADDRESS}`)
  await waitForHeading(b, 'Page not found')
  const typed = await b.run(shownAddress)
  check('the unknown address is shown as text', typed === UNKNOWN_ADDRESS, String(typed))
  await owlShown(b, 'notFound', 'the Page not found screen')
  const marked = await b.run(activeInSidebar)
  check('the Page not found screen keeps the sidebar with nothing marked active', marked.length === 0 && (await b.text()).includes('Token ledger'), marked.join(' | '))
  const text = await b.text()
  check('the Page not found screen offers Go to Overview, Machines and VMs', ['Go to Overview', 'Machines', 'VMs'].every((label) => text.includes(label)))
  await noSideScroll(b, 'the Page not found screen')
  await b.shot(shotName)
  await b.page.click('main .empty a.btn.green')
  await waitForHeading(b, 'Overview')
  check('Go to Overview lands on Overview', (await b.run(heading)) === 'Overview')
  await b.go('#/machines/')
  await waitForHeading(b, 'Machines')
  check('a real address with a trailing slash still works', (await b.run(heading)) === 'Machines')
}

/** Visits an address made of markup, encoded the way a browser sends it, and checks that it stays text. */
export async function hostilePageNotFound(b: Browse): Promise<void> {
  await b.go(`#/${encodeURIComponent(HOSTILE_ADDRESS.slice(1))}`)
  await waitForHeading(b, 'Page not found')
  const typed = await b.run(shownAddress)
  const ran = (await b.run(() => window.__xss)) !== undefined || (await b.page.$('main img[src="x"]')) !== null
  check('a hostile address is shown as text, not run', typed === HOSTILE_ADDRESS && !ran, String(typed))
  await b.go('#/')
}
