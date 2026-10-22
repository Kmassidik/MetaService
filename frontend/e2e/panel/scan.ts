// Find machines: a scan lists the devices with where they were seen, marks one that already runs the Agent, and Add on a row opens Add a machine.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { SCAN_PREFIX } from '../support/root.ts'

const SCAN_WAIT_MS = 20000
const SHORT_WAIT_MS = 10000
const FOUND_ENDS = ['.1', '.40', '.60', '.90']
const ROW_TO_ADD = `${SCAN_PREFIX}.40`

export async function scanScenario(b: Browse): Promise<void> {
  await b.go('#/machines/find')
  await b.until(() => document.body.innerText.includes('Looks at'), {})
  // A scan runs only when asked for; the first time there is nothing to show yet.
  await b.until(() => document.body.innerText.includes('Nothing scanned yet'), {})
  check('before the first scan the owl is shown with the empty message', (await b.page.$$('img[data-owl=emptyMachines]')).length === 1)
  await b.shot('scan-empty.png')
  await b.click('Scan now')
  await b.until(() => document.body.innerText.includes('Agent running'), { timeout: SCAN_WAIT_MS })
  const shown = await b.text()
  check('a scan lists the devices with where they were seen', FOUND_ENDS.every((end) => shown.includes(`${SCAN_PREFIX}${end}`)) && shown.includes('nmap'))
  check('a device answering on the Agent port is marked', shown.includes('Agent running'))
  check('rows have no checkbox and no machine name to fill in', !(await b.page.$('input[type=checkbox]')) && !(await b.page.$('input[aria-label^="Machine name for"]')))
  check('the owl is gone once devices are listed', (await b.page.$$('img[data-owl]')).length === 0)
  await b.shot('scan-results.png')
  await b.page.click(`button[aria-label="Add ${ROW_TO_ADD}"]`)
  await b.page.waitForSelector('dialog[open] #connect-host', { timeout: SHORT_WAIT_MS })
  const filledIn = await b.run(() => document.querySelector<HTMLInputElement>('dialog[open] #connect-host')?.value ?? '')
  check("Add on a row opens Add a machine with that row's address", /Add a machine/.test(await b.dialogText()) && filledIn === ROW_TO_ADD, filledIn)
  await b.click('Cancel')
  await thisComputerCanBeAdded(b)
  await b.go('#/machines')
}

/** The scan's own address is the real one of the machine running the test, so the page is told that the row at .40 is this computer: it must say so and still have Add. */
async function thisComputerCanBeAdded(b: Browse): Promise<void> {
  await b.run((address) => {
    const real = window.fetch.bind(window)
    window.fetch = async (...args: Parameters<typeof fetch>) => {
      const reply = await real(...args)
      if (!String(args[0]).endsWith('/api/scan/setup')) return reply
      const body: { own_addresses?: string[] } = await reply.json()
      return new Response(JSON.stringify({ ...body, own_addresses: [...(body.own_addresses ?? []), address] }), { status: reply.status, headers: { 'content-type': 'application/json' } })
    }
  }, ROW_TO_ADD)
  await b.go('#/machines')
  await b.go('#/machines/find')
  await b.page.waitForSelector(`button[aria-label="Add ${ROW_TO_ADD}"]`, { timeout: SHORT_WAIT_MS })
  const row = await b.run((address) => [...document.querySelectorAll<HTMLElement>('[role=row]')].find((item) => item.innerText.includes(address))?.innerText ?? '', ROW_TO_ADD)
  check('the computer MetaService runs on says "This computer" and still has an Add button', /This computer/.test(row) && /Add/.test(row), row)
  await b.shot('scan-this-computer.png')
}
