// The VMs item in the sidebar: one plain link to All VMs (no dropdown, no Create VM item), marked on the VMs pages, unmarked elsewhere. The Machines dropdown is left as it was.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'

const GREEN = 'rgb(0, 245, 109)'
const VMS_LINK = 'aside.side nav a[href="#/vms"]'
const SHORT_WAIT_MS = 10000

const isMarked = (b: Browse) => b.run((selector) => document.querySelector(selector)?.getAttribute('aria-current') === 'page', VMS_LINK)
const stripeOfLink = (b: Browse) => b.run((selector) => { const link = document.querySelector(selector); return link ? getComputedStyle(link).borderLeftColor : '' }, VMS_LINK)
const infrastructure = (b: Browse) => b.page.$$eval('aside.side nav > div:nth-of-type(2) > :is(a, button)', (nodes) => nodes.map((node) => `${node.tagName.toLowerCase()}:${node.textContent?.trim()}`))

export async function vmsIsOneLink(b: Browse): Promise<void> {
  await b.go('#/')
  await b.page.reload({ waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Overview', { timeout: SHORT_WAIT_MS })
  const order = await infrastructure(b)
  check('the Infrastructure group has the Machines dropdown button, then VMs as a plain link', JSON.stringify(order) === JSON.stringify(['button:Machines', 'a:VMs']), JSON.stringify(order))
  check('VMs has no chevron, no dropdown and no Create VM item', await b.run((selector) => {
    const link = document.querySelector(selector)
    return link !== null && link.querySelector('.chev') === null && document.querySelector('#vms-menu') === null && !/Create VM/.test(document.querySelector<HTMLElement>('aside.side')?.innerText ?? '')
  }, VMS_LINK))
  check('VMs points to All VMs and is not marked on the Overview', (await b.run((selector) => document.querySelector(selector)?.getAttribute('href'), VMS_LINK)) === '#/vms' && !(await isMarked(b)))
  await b.click('Machines')
  check('the Machines dropdown still opens with Machine list and Find machines', JSON.stringify(await b.page.$$eval('#machines-menu a', (links) => links.map((link) => link.textContent?.trim()))) === JSON.stringify(['Machine list', 'Find machines']))
  await b.click('Machines')
}

export async function vmsLinkOnItsPages(b: Browse): Promise<void> {
  await b.go('#/vms')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'All VMs', { timeout: SHORT_WAIT_MS })
  check('on All VMs the VMs link is marked, with the green stripe', (await isMarked(b)) && (await stripeOfLink(b)) === GREEN)
  await b.go('#/vms?machine=mac-mini')
  check('with a machine in the address the VMs link is still marked', await isMarked(b))
  await b.go('#/vms/create')
  await b.page.waitForSelector('dialog[open]')
  check('with the Create VM window open the VMs link is still marked', await isMarked(b))
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
  await b.go('#/machines/details?id=mac-mini&vm=wl-1')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'demo', { timeout: SHORT_WAIT_MS })
  check('on a VM\'s own page the VMs link is not marked (as before)', !(await isMarked(b)))
  await b.go('#/vms')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'All VMs', { timeout: SHORT_WAIT_MS })
  await b.shot('vms-sidebar-link.png')
}
