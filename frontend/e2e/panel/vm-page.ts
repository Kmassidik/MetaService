// The VM page (the MAAS detail page for one VM): reached from all three Deployments views, its four tabs, Stop and Start, the MAAS-only parts staying hidden,
// and Delete (confirm first, then back to the machine's page).
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from './machines.ts'

const VM = 'page-box'
const MACHINE_URL_END = '#/machines/details?id=agent-mac'
const SHORT_WAIT_MS = 10000
const ACTION_WAIT_MS = 20000
const TABS = ['Overview', 'Monitoring', 'Access', 'Danger']
const MAAS_ONLY_WORDS = /Web terminal|Restart|Rename/
type CreateVm = (b: Browse, name: string) => Promise<void>

const vmUrlEnd = (vmId: string) => `${MACHINE_URL_END}&vm=${vmId}`
const onTheVmPage = (b: Browse) => b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, VM)

async function backToDeployments(b: Browse): Promise<void> {
  await b.go(MACHINE_URL_END)
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'agent-mac', { timeout: SHORT_WAIT_MS })
  await openTab(b, 'Deployments')
  await b.page.waitForSelector('.segmented')
}

/** The id Root gave the VM (its name is only what it is called), read from its link in the Table view. */
async function theVmId(b: Browse): Promise<string> {
  await backToDeployments(b)
  await pickView(b, 'Table')
  await b.page.waitForSelector('td.c-name a')
  const href = await b.run((name) => [...document.querySelectorAll<HTMLAnchorElement>('td.c-name a')].find((link) => link.textContent?.trim() === name)?.getAttribute('href') ?? '', VM)
  const id = new URLSearchParams(href.split('?')[1]).get('vm')
  if (!id) throw new Error(`no link to ${VM} in the Table view: ${href}`)
  return id
}

async function opensFrom(b: Browse, view: string, link: string, vmId: string): Promise<void> {
  await backToDeployments(b)
  await pickView(b, view)
  await b.page.waitForSelector(link)
  await b.run((selector, name) => [...document.querySelectorAll<HTMLElement>(selector)].find((entry) => entry.getAttribute('aria-label')?.includes(name) || entry.textContent?.trim() === name)?.click(), link, VM)
  await onTheVmPage(b)
  check(`a VM opens its page from the ${view} view`, b.page.url().endsWith(vmUrlEnd(vmId)), b.page.url())
}

async function theFourTabs(b: Browse): Promise<void> {
  const tabs = await b.run(() => [...document.querySelectorAll('[role=tab]')].map((tab) => tab.textContent?.trim()))
  check('the VM page has the tabs Overview, Monitoring, Access and Danger', JSON.stringify(tabs) === JSON.stringify(TABS), JSON.stringify(tabs))
  for (const tab of TABS) {
    await openTab(b, tab)
    check(`the ${tab} tab shows something`, await b.run(() => (document.querySelector<HTMLElement>('.tabbody')?.innerText.trim().length ?? 0) > 0), tab)
  }
  await openTab(b, 'Danger')
  check('the Danger tab offers Delete instance', (await b.text()).includes('Delete instance'))
  check('the parts MAAS has but MetaService has no data for stay hidden', !MAAS_ONLY_WORDS.test(await b.text()))
}

async function stopThenStart(b: Browse): Promise<void> {
  await b.click('Stop')
  await b.until(() => [...document.querySelectorAll('.phead button')].some((button) => button.textContent?.trim() === 'Start'), { timeout: ACTION_WAIT_MS })
  check('Stop on the VM page stops it and the button becomes Start', true)
  await b.click('Start')
  await b.until(() => [...document.querySelectorAll('.phead button')].some((button) => button.textContent?.trim() === 'Stop'), { timeout: ACTION_WAIT_MS })
  check('Start on the VM page starts it again', true)
}

async function deleteGoesBackToTheMachine(b: Browse, vmId: string): Promise<void> {
  await openTab(b, 'Danger')
  await b.click('Delete instance')
  await b.page.waitForSelector('dialog[open]')
  check('Delete asks first and says a backup is made', (await b.dialogText()).includes('makes a backup of it first'))
  check('nothing is deleted before the answer', b.page.url().endsWith(vmUrlEnd(vmId)), b.page.url())
  await b.click('Back up and delete')
  await b.until((end) => location.hash === end, { timeout: ACTION_WAIT_MS }, MACHINE_URL_END)
  check('after Delete the page is the machine page again', b.page.url().endsWith(MACHINE_URL_END), b.page.url())
}

export async function vmPageScenario(b: Browse, createVm: CreateVm): Promise<void> {
  await createVm(b, VM)
  await b.until((name) => document.body.innerText.includes(name), { timeout: ACTION_WAIT_MS }, VM)
  const vmId = await theVmId(b)
  await opensFrom(b, 'Building', '.bv-name', vmId)
  await opensFrom(b, 'Building', '.bv-apt .bv-hit', vmId)
  await opensFrom(b, 'Cards', '.card a.nm', vmId)
  await opensFrom(b, 'Table', 'td.c-name a', vmId)
  await b.shot('vm-page.png')
  await theFourTabs(b)
  await openTab(b, 'Overview')
  await stopThenStart(b)
  await deleteGoesBackToTheMachine(b, vmId)
}
