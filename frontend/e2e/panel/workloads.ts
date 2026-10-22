// A machine's own page and its VMs: creating, listing in the three views, stopping, starting, deleting, and a request that fits nowhere.
import { check } from '../support/check.ts'
import { imageListArrived } from '../support/images.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from './machines.ts'
import { vmPageScenario } from './vm-page.ts'
import { startAgent, type World } from './world.ts'

const SHORT_WAIT_MS = 10000
const ROW_WAIT_MS = 15000
const AGENT_WAIT_MS = 20000
const TOO_MUCH_RAM_MB = '500'
const NEW_VM = 'build-box'

/** Presses a button in the row of one VM, on a machine's VMs tab. */
const rowButton = (b: Browse, vm: string, label: string) =>
  b.run((name, wanted) => [...document.querySelectorAll('tbody tr')].find((row) => row instanceof HTMLElement && row.innerText.includes(name))?.querySelectorAll('button').forEach((button) => button.getAttribute('aria-label') === wanted && button.click()), vm, label)

const rowHas = (b: Browse, vm: string, label: string) =>
  b.until((name, wanted) => [...document.querySelectorAll<HTMLTableRowElement>('tbody tr')].find((row) => row.innerText.includes(name))?.querySelector(`button[aria-label="${wanted}"]`) != null, { timeout: ROW_WAIT_MS }, vm, label)

const machineHeading = (b: Browse, name: string, timeout = SHORT_WAIT_MS) => b.until((wanted) => document.querySelector('.phead h1')?.textContent === wanted, { timeout }, name)

async function openTheMachine(b: Browse): Promise<void> {
  await b.go('#/machines')
  await b.until(() => document.body.innerText.includes('agent-mac'), { timeout: AGENT_WAIT_MS })
  await b.run(() => [...document.querySelectorAll('article')].find((card) => card.innerText.includes('agent-mac'))?.querySelector<HTMLElement>('a.btn')?.click())
  await machineHeading(b, 'agent-mac')
  check('opening a machine goes to /machines/details?id=<machine>', b.page.url().endsWith('#/machines/details?id=agent-mac'), b.page.url())
  const shown = await b.text()
  check('the machine page has its breadcrumb and opens on Live', /Machines › agent-mac/.test(shown) && (await b.run(() => document.querySelector('[role=tab][aria-selected=true]')?.textContent?.trim())) === 'Live')
  await b.shot('machine-detail.png')
  await openTab(b, 'Environment')
  const facts = await b.text()
  check('the machine page shows its facts on the Environment tab', /ID\s*agent-mac/i.test(facts) && /Memory/i.test(facts))
  await openTab(b, 'Live')
  const sidebar = await b.page.$eval('aside.side', (side) => side instanceof HTMLElement ? side.innerText : '')
  check('the sidebar has no Deployments page: the VMs are inside the machine, on the VMs tab', !/Deployments$/m.test(sidebar) && /VMs \(0\)/.test(shown))
}

export async function createAVm(b: Browse, name = NEW_VM): Promise<void> {
  await b.click('＋ Create a VM here')
  await b.page.waitForSelector('dialog[open] #vm-create-name')
  await imageListArrived(b)
  await b.page.type('dialog[open] #vm-create-name', 'Bad Name')
  const submitOff = await b.run(() => document.querySelector<HTMLButtonElement>('dialog[open] button[type=submit]')?.disabled ?? false)
  check('a bad workload name disables Create and explains', submitOff && (await b.text()).includes('Use lowercase letters'))
  await b.type('dialog[open] #vm-create-name', name)
  check("a VM made from a machine's own page can only go to that machine", await b.run(() => {
    const label = [...document.querySelectorAll<HTMLElement>('dialog[open] label')].find((entry) => entry.innerText.startsWith('Machine'))
    const select = label?.querySelector('select')
    return select?.value === 'agent-mac' && select.options.length === 1 && select.disabled
  }))
  await b.click('Create')
  await b.until(() => !document.querySelector('dialog[open]'), { timeout: SHORT_WAIT_MS })
}

async function itsActivity(b: Browse): Promise<void> {
  await b.go('#/health')
  await b.until(() => /Create\s+build-box[\s\S]*succeeded/.test(document.body.innerText), { timeout: AGENT_WAIT_MS })
  check('a new workload shows in recent activity as succeeded', true)
  await b.go('#/machines/details?id=agent-mac')
  await machineHeading(b, 'agent-mac')
  await openTab(b, 'Activity')
  await b.until(() => /Create\s+build-box[\s\S]*succeeded/.test(document.body.innerText), { timeout: ROW_WAIT_MS })
  check('its Activity tab shows what happened on this machine only', !/dgx-spark/.test(await b.text()))
}

async function theThreeViews(b: Browse): Promise<void> {
  await openTab(b, 'VMs')
  await b.until(() => document.body.innerText.includes('build-box'), { timeout: ROW_WAIT_MS })
  await b.page.waitForSelector('.segmented')
  await pickView(b, 'Building')
  await b.page.waitForSelector('.bv')
  await b.shot('deployments-building.png', true)
  const building = await b.text()
  check('the VMs tab opens as the building view with the VM as an apartment, and no allocated-disk headline (the monitor above says what is real)',
    !/Disk allocated/.test(building) && /1\/1 running/.test(building) && await b.run(() => [...document.querySelectorAll('.bv-apt')].some((apartment) => /build-box/.test(apartment.getAttribute('aria-label') ?? ''))))
  const edges = await b.run(() => {
    const left = (selector: string) => document.querySelector(selector)?.getBoundingClientRect().left ?? -1
    const right = (selector: string) => document.querySelector(selector)?.getBoundingClientRect().right ?? -1
    const top = (selector: string) => document.querySelector(selector)?.getBoundingClientRect().top ?? -1
    return { barLeft: left('.runs'), buildingLeft: left('.bv-building'), buttonRight: right('.bar-row .btn.green'), sideRight: right('.bv-side'), buildingTop: top('.bv-building'), sideTop: top('.bv-side'), buildingRight: right('.bv-building'), sideLeft: left('.bv-side') }
  })
  const aligned = (one: number, other: number) => Math.abs(one - other) <= 1
  check('the building lines up with the toolbar: same left edge, the card ends where New VM ends, both start at the same height',
    aligned(edges.barLeft, edges.buildingLeft) && aligned(edges.buttonRight, edges.sideRight) && aligned(edges.buildingTop, edges.sideTop) && edges.sideLeft - edges.buildingRight >= 16, JSON.stringify(edges))
  await pickView(b, 'Cards')
  await b.until(() => [...document.querySelectorAll('.card')].some((card) => card instanceof HTMLElement && card.innerText.includes('build-box')), { timeout: SHORT_WAIT_MS })
  check('the Cards view shows the VM with its actions', await b.run(() => [...document.querySelectorAll('.card')].some((card) => card instanceof HTMLElement && /build-box/.test(card.innerText) && card.querySelector('button[aria-label="Stop"]') !== null)))
  await b.shot('deployments-cards.png')
  await pickView(b, 'Table')
  await b.page.waitForSelector('tbody tr')
  await b.shot('workloads.png', true)
  check("the workload appears in its machine's VMs tab", (await b.text()).includes(NEW_VM))
}

async function stopStartDelete(b: Browse): Promise<void> {
  await rowButton(b, NEW_VM, 'Stop')
  await rowHas(b, NEW_VM, 'Start')
  check('Stop turns the button into Start', true)
  await rowButton(b, NEW_VM, 'Start')
  await rowHas(b, NEW_VM, 'Stop')
  await rowButton(b, NEW_VM, 'Delete')
  await b.page.waitForSelector('dialog[open]')
  check('delete says a backup is made first', (await b.text()).includes('makes a backup of it first'))
  await b.click('Delete VM')
  await b.until(() => !document.body.innerText.includes('build-box') || /Delete\s+[\s\S]*succeeded/.test(document.body.innerText), { timeout: AGENT_WAIT_MS })
  await b.until(() => ![...document.querySelectorAll('tbody tr')].some((row) => row instanceof HTMLElement && row.innerText.includes('build-box')), { timeout: AGENT_WAIT_MS })
  check('a deleted workload disappears', true)
}

async function aRequestThatFitsNowhere(b: Browse): Promise<void> {
  await b.click('＋ Create a VM here')
  await b.page.waitForSelector('dialog[open] #vm-create-name')
  await imageListArrived(b)
  await b.page.type('dialog[open] #vm-create-name', 'too-big')
  await b.run((megabytes) => {
    const label = [...document.querySelectorAll<HTMLElement>('dialog[open] label')].find((entry) => entry.innerText.startsWith('RAM'))
    const ram = label?.querySelector('input')
    if (!ram) throw new Error('no RAM field')
    ram.value = megabytes
    ram.dispatchEvent(new Event('input', { bubbles: true }))
  }, TOO_MUCH_RAM_MB)
  await b.click('Create')
  await b.page.waitForSelector('dialog[open] [role=alert]', { timeout: SHORT_WAIT_MS })
  const refusal = await b.page.$eval('dialog[open] [role=alert]', (alert) => alert instanceof HTMLElement ? alert.innerText : '')
  check('a request that fits nowhere shows the numbers', refusal.includes('needs 512000 MB RAM'), refusal)
  await b.click('Cancel')
}

export async function workloadScenario(b: Browse, world: World): Promise<void> {
  const agent = await startAgent(world)
  try {
    await openTheMachine(b)
    await createAVm(b)
    await itsActivity(b)
    await theThreeViews(b)
    await stopStartDelete(b)
    await vmPageScenario(b, createAVm)
    await aRequestThatFitsNowhere(b)
  } finally {
    agent.kill()
  }
}
