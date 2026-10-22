// The All VMs page: the table of every VM, the Machine filter kept in the address, the empty states, a row opening the VM, and hostile text staying text.
import { check } from '../support/check.ts'
import { noSideScroll, owlShown } from '../support/owls.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from '../panel/machines.ts'
import { CONTAINER_MACHINE, CONTAINER_VM, OFFLINE_MACHINE, SICK_MACHINE } from './fleet.ts'

const SHORT_WAIT_MS = 10000
const TABLE_ROWS = 'table[aria-label="VMs"] tbody tr'
const FILTER = '#vm-machine'
const KIND_CELL = 3

export const heading = (b: Browse) => b.run(() => document.querySelector('.phead h1')?.textContent ?? '')
export const crumb = (b: Browse) => b.run(() => document.querySelector('.phead .crumb')?.textContent?.trim() ?? '')
export const filterValue = (b: Browse) => b.run((selector) => document.querySelector<HTMLSelectElement>(selector)?.value ?? null, FILTER)

/** Each row of the table as its cells' text: name, machine, kind, state, vCPU, RAM, disk. */
export const tableRows = (b: Browse) =>
  b.page.$$eval(TABLE_ROWS, (rows) => rows.map((row) => [...row.querySelectorAll('td')].map((cell) => (cell instanceof HTMLElement ? cell.innerText : '').trim().replace(/\s+/g, ' '))))

export async function openAllVms(b: Browse, hash = '#/vms'): Promise<void> {
  await b.go(hash)
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'All VMs', { timeout: SHORT_WAIT_MS })
}

export async function emptyStates(b: Browse): Promise<void> {
  await openAllVms(b)
  const shown = await b.text()
  check('with no machines at all, All VMs says there are no VMs yet and offers Create VM', /No VMs yet/.test(shown) && (await b.run(() => [...document.querySelectorAll('.empty a')].some((link) => link.textContent?.includes('Create VM')))))
  check('with no machines there is no Machine filter and the count says 0 VMs', (await filterValue(b)) === null && (await crumb(b)).endsWith('0 VMs'))
  await owlShown(b, 'emptyVms', 'the empty All VMs page')
  check('the empty All VMs page keeps its sentence next to the owl', /No VMs yet\. Make the first one on any of your machines\./.test(shown))
  await b.shot('vms-empty.png')
}

export async function fullTable(b: Browse): Promise<void> {
  await openAllVms(b)
  await b.page.waitForSelector(TABLE_ROWS)
  const rows = await tableRows(b)
  const names = rows.map((cells) => `${cells[1]}/${cells[0]}`)
  check('All VMs lists the VMs of every machine, sorted by machine name then VM name', JSON.stringify(names) === JSON.stringify([`${CONTAINER_MACHINE}/${CONTAINER_VM}`, 'dgx-spark/demo', 'mac-mini/demo']), JSON.stringify(names))
  check('a row shows name, machine, kind, state, vCPU, RAM and disk', JSON.stringify(rows[2]?.map((cell) => cell.toLowerCase())) === JSON.stringify(['demo', 'mac-mini', 'vm', 'running', '2', '2 gb', '20 gb', '▸ terminal']), JSON.stringify(rows[2]))
  check('a container is listed as a container, with its own sizes', rows[0]?.[2] === 'container' && rows[0][5] === '512 MB' && rows[0][6] === '5 GB')
  check('the header counts the VMs and the machines they are on', (await crumb(b)) === 'Infrastructure › 3 VMs on 3 machines', await crumb(b))
  check('the table shows no script from machine data', (await b.run(() => window.__xss)) === undefined && (await b.page.$('img[src="x"]')) === null)
  await b.shot('vms-all.png', true)
}

export async function filtering(b: Browse): Promise<void> {
  const options = await b.page.$$eval(`${FILTER} option`, (list) => list.map((option) => option.textContent?.trim()))
  check('the Machine filter offers All machines and then each machine by name', JSON.stringify(options) === JSON.stringify(['All machines', CONTAINER_MACHINE, 'dgx-spark', 'mac-mini', OFFLINE_MACHINE, SICK_MACHINE]), JSON.stringify(options))
  await b.page.select(FILTER, 'mac-mini')
  await b.until(() => location.hash === '#/vms?machine=mac-mini', { timeout: SHORT_WAIT_MS })
  const rows = await tableRows(b)
  check('choosing a machine narrows the table to its VMs and the address keeps the choice', rows.length === 1 && rows[0]?.[1] === 'mac-mini')
  check('the header follows the filter', (await crumb(b)) === 'Infrastructure › 1 VM on 1 machine', await crumb(b))
  await b.shot('vms-filtered.png')
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.page.waitForSelector(TABLE_ROWS)
  check('after a reload the filter and the table are the same', (await filterValue(b)) === 'mac-mini' && (await tableRows(b)).length === 1)
  await openAllVms(b, '#/vms?machine=no-such-machine')
  await b.page.waitForSelector(TABLE_ROWS)
  check('an unknown machine in the address falls back to All machines', (await filterValue(b)) === '' && (await tableRows(b)).length === 3)
  await openAllVms(b, '#/vms?machine=Bad%20Name%3Cb%3E')
  await b.page.waitForSelector(TABLE_ROWS)
  check('an invalid machine in the address falls back to All machines', (await filterValue(b)) === '' && (await tableRows(b)).length === 3)
  await openAllVms(b, `#/vms?machine=${OFFLINE_MACHINE}`)
  await b.until(() => document.body.innerText.includes('No VMs on this machine.'), { timeout: SHORT_WAIT_MS })
  check('a machine without VMs says so, with Create VM for that machine', await b.run((machine) => [...document.querySelectorAll<HTMLAnchorElement>('.empty a')].some((link) => link.getAttribute('href') === `#/vms/create?machine=${machine}`), OFFLINE_MACHINE))
  await owlShown(b, 'emptyVms', 'All VMs narrowed to a machine without VMs')
  await b.shot('vms-none-on-machine.png')
  await b.go(`#/machines/details?id=${OFFLINE_MACHINE}`)
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  await b.until(() => document.body.innerText.includes('No VMs on this machine yet.'), { timeout: SHORT_WAIT_MS })
  await owlShown(b, 'emptyVms', 'the machine page VMs tab without VMs')
  await noSideScroll(b, 'the machine page VMs tab without VMs')
}

export async function openingARow(b: Browse): Promise<void> {
  await openAllVms(b)
  await b.page.waitForSelector(TABLE_ROWS)
  const index = (await tableRows(b)).findIndex((cells) => cells[1] === 'mac-mini')
  const kindCell = (await b.page.$$(`${TABLE_ROWS} td:nth-child(${KIND_CELL})`))[index]
  if (!kindCell) throw new Error('the mac-mini row has no kind cell')
  await kindCell.click()
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'demo', { timeout: SHORT_WAIT_MS })
  check('clicking anywhere on a row opens that VM\'s page', b.page.url().endsWith('#/machines/details?id=mac-mini&vm=wl-1'), b.page.url())
  await openAllVms(b)
  await b.page.waitForSelector(TABLE_ROWS)
  await b.page.click(`${TABLE_ROWS}:nth-child(3) td:nth-child(2) a`)
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'mac-mini', { timeout: SHORT_WAIT_MS })
  check('the machine name in a row opens the machine\'s page, not the VM', b.page.url().endsWith('#/machines/details?id=mac-mini'), b.page.url())
}
