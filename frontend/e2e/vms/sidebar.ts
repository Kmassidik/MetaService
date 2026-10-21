// The VMs dropdown in the sidebar: closed by default, two items and no machine names, opens by itself on a VMs page, marks the page being looked at, and marks nothing elsewhere.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'

const GREEN = 'rgb(0, 245, 109)'
const MENU_BUTTON = 'aside.side nav button[aria-controls="vms-menu"]'
const MENU_ITEMS = '#vms-menu a'
const SHORT_WAIT_MS = 10000

const expanded = (b: Browse) => b.run((selector) => document.querySelector(selector)?.getAttribute('aria-expanded'), MENU_BUTTON)
const itemTexts = (b: Browse) => b.page.$$eval(MENU_ITEMS, (links) => links.map((link) => link.textContent?.trim() ?? ''))
const markedItems = (b: Browse) => b.page.$$eval(MENU_ITEMS, (links) => links.filter((link) => link.getAttribute('aria-current') === 'page').map((link) => link.textContent?.trim() ?? ''))
const menuIsOpen = (b: Browse) => b.run(() => document.querySelector('#vms-menu') !== null)

/** The colour of the stripe beside the marked item, which is how the page being looked at is shown. */
const stripeOfMarked = (b: Browse) => b.run((selector) => {
  const marked = document.querySelector(selector + '[aria-current="page"]')
  return marked ? getComputedStyle(marked).borderLeftColor : ''
}, MENU_ITEMS)

export async function vmsDropdown(b: Browse): Promise<void> {
  await b.go('#/')
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Overview', { timeout: SHORT_WAIT_MS })
  check('the VMs dropdown sits below Machines in Infrastructure and starts closed on the Overview', (await expanded(b)) === 'false' && !(await menuIsOpen(b)))
  const order = await b.page.$$eval('aside.side nav > div:nth-of-type(2) > :is(a, button)', (nodes) => nodes.map((node) => node.textContent?.trim()))
  check('the Infrastructure group has Machines, then VMs', JSON.stringify(order) === JSON.stringify(['Machines', 'VMs']), JSON.stringify(order))
  await b.page.click(MENU_BUTTON)
  await b.page.waitForSelector('#vms-menu')
  check('pressing VMs opens it and says so', (await expanded(b)) === 'true')
  check('it has exactly All VMs and Create VM, and no machine names', JSON.stringify(await itemTexts(b)) === JSON.stringify(['All VMs', 'Create VM']), JSON.stringify(await itemTexts(b)))
  check('on the Overview nothing in it is marked', (await markedItems(b)).length === 0)
  await b.page.click(MENU_BUTTON)
  check('pressing it again closes it', !(await menuIsOpen(b)) && (await expanded(b)) === 'false')
}

export async function vmsDropdownOnItsPages(b: Browse): Promise<void> {
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.go('#/vms')
  await b.page.waitForSelector('#vms-menu')
  check('it opens by itself on the All VMs page', (await expanded(b)) === 'true')
  check('All VMs is the marked item, with the green stripe', JSON.stringify(await markedItems(b)) === JSON.stringify(['All VMs']) && (await stripeOfMarked(b)) === GREEN)
  check('the Machines dropdown has nothing marked there', await b.run(() => document.querySelector('#machines-menu a[aria-current="page"]') === null))
  await b.go('#/vms/create')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Create VM', { timeout: SHORT_WAIT_MS })
  check('Create VM is the marked item on the Create VM page', JSON.stringify(await markedItems(b)) === JSON.stringify(['Create VM']))
  await b.go('#/vms?machine=mac-mini')
  check('with a machine in the address All VMs is still the marked item', JSON.stringify(await markedItems(b)) === JSON.stringify(['All VMs']))
  await b.go('#/machines/details?id=mac-mini&vm=wl-1')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'demo', { timeout: SHORT_WAIT_MS })
  check('on a VM\'s own page nothing in the VMs dropdown is marked', (await markedItems(b)).length === 0)
  await b.shot('vms-sidebar-open.png')
}
