// The Create VM window is ONE window for every way in. Its size and runtime are native selects: lines that do not fit are off with the reason, Custom opens the boxes, the caption follows the runtime.
// An empty name gets a generated one, five quick clicks send one order that carries the choices, and on a phone nothing scrolls sideways while the footer stays in reach.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { CREATE_FORM, NAME, RUNTIME, SIZE, captionOf, choose, closeProgress, createFormCount, fieldValue, imageListArrived, imageState, lines, openedMenu, selectValue, setField } from '../support/createVm.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from '../panel/machines.ts'
import { closeWithEscape, openCreate } from './create.ts'
import { CONTAINER_MACHINE, OFFLINE_MACHINE } from './fleet.ts'
import { openAllVms } from './list.ts'

const SHORT_WAIT_MS = 10000
const MADE_WAIT_MS = 40000
const HELPER_MACHINE = 'agent-mac'
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }
const GENERATED_NAME = /^vm-[0-9a-f]{4}$/
const QUICK_CLICKS = 5
const SMALL = { cpu: 1, ram_mb: 2048, disk_gb: 20 }
const RAM_TOO_BIG_TEXT = 'RAM (GB) must be between 0.5 and 1024.'
const RAM_BEYOND_LIMIT_GB = '2000'
const REFUSING_RAM_GB = '500'
const OTHER_PAGES = ['#/overview', '#/machines', '#/vms', '#/machines/details?id=mac-mini']
const CONTAINER_CAPTION = "Fast stop and wake. Shares the machine's core, so it starts in seconds and uses little memory. Best for agents and apps."
const VM_CAPTION = 'A full computer with its own core: a stronger wall, slower start, more memory. Needs virtualization on the machine.'
const MAC_CAPTION = "On a Mac both run inside Apple's own small VM."
const SECTION_LABELS = ['ON HOST', 'SERVER IMAGE', 'INSTALL ON TOP (optional)', 'INSTANCE SIZE', 'RUNTIME ENVIRONMENT', 'INSTANCE NAME (optional)']

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
const closed = (b: Browse) => b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
const openWindow = (b: Browse) => b.page.waitForSelector('dialog[open] form[aria-label="Create VM"]', { timeout: SHORT_WAIT_MS })

async function exactlyOne(b: Browse, where: string): Promise<void> {
  await openWindow(b)
  const count = await createFormCount(b)
  check(`${where}: exactly one Create VM window is in the page`, count.forms === 1 && count.openDialogs === 1 && count.nameBoxes === 1, JSON.stringify(count))
  await b.page.keyboard.press('Escape')
  await closed(b)
  await b.until((form) => document.querySelector(form) === null, { timeout: SHORT_WAIT_MS }, CREATE_FORM)
  const after = await createFormCount(b)
  check(`${where}: closed, no Create VM form is left in the page`, after.forms === 0 && after.nameBoxes === 0, JSON.stringify(after))
}

/** Every way in opens the same single window, and no other page has a create form of its own. */
export async function oneWindowFromEveryWayIn(b: Browse): Promise<void> {
  await openAllVms(b)
  await b.page.click('.phead .sp a.btn.green')
  await exactlyOne(b, 'All VMs, the + Create VM button')

  await openAllVms(b, `#/vms?machine=${OFFLINE_MACHINE}`)
  await b.until(() => document.body.innerText.includes('No VMs on this machine.'), { timeout: SHORT_WAIT_MS })
  await b.page.click('.empty a.btn')
  await exactlyOne(b, 'All VMs, the empty state')

  await openCreate(b)
  await exactlyOne(b, 'the old #/vms/create address')

  await b.go(`#/machines/details?id=${OFFLINE_MACHINE}`)
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  await b.until(() => document.body.innerText.includes('No VMs on this machine yet.'), { timeout: SHORT_WAIT_MS })
  await b.click('＋ Create a VM')
  await exactlyOne(b, 'a machine page, the empty state')

  await b.go('#/machines/details?id=mac-mini')
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  await b.click('＋ New VM')
  await exactlyOne(b, 'a machine page, the + New VM button')

  for (const page of OTHER_PAGES) {
    await b.go(page)
    const count = await createFormCount(b)
    check(`${page} has no create form of its own`, count.forms === 0 && count.nameBoxes === 0 && count.openDialogs === 0, JSON.stringify(count))
  }
}

/** The sections come in the mockup's order with their small uppercase labels. */
export async function sectionsInOrder(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  const labels = await b.page.$$eval('dialog[open] form .label', (list) => list.map((label) => (label instanceof HTMLElement ? label.innerText.replace(/\s+/g, ' ').trim() : '')))
  check('the sections are On host, Server image, Install on top, Instance size, Runtime environment (a Mac has no GPU line), Instance name, in capitals', JSON.stringify(labels) === JSON.stringify(SECTION_LABELS), JSON.stringify(labels))
  const frame = await b.run(() => {
    const dialog = document.querySelector('dialog[open]')?.getBoundingClientRect()
    const title = document.querySelector('dialog[open] h3')
    return { width: Math.round(dialog?.width ?? 0), title: title ? getComputedStyle(title).fontSize : '' }
  })
  check('the window is 760 px wide with a 17 px title', frame.width === 760 && frame.title === '17px', JSON.stringify(frame))
  await b.shot('vms-create-default.png')
  await closeWithEscape(b)
}

/** The size select: lines that do not fit are off with the reason in brackets, and Custom opens the three boxes with the usual limits; a preset hides them again. */
export async function sizeSelect(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  const roomy = await lines(b, SIZE)
  check('the size select reads Small, Medium (Recommended), Large and Custom with their specs', JSON.stringify(roomy.map((line) => line.text)) === JSON.stringify(['Small — 1 vCPU · 2GB RAM · 20GB Disk', 'Medium — 2 vCPU · 4GB RAM · 40GB Disk (Recommended)', 'Large — 4 vCPU · 8GB RAM · 60GB Disk', 'Custom — Configure specs manually...']), JSON.stringify(roomy))
  check('with no machine defaults Medium is picked', (await selectValue(b, SIZE)) === 'medium')
  check('the three boxes are not there while a preset is picked', (await fieldValue(b, 'CPU')) === null)
  await choose(b, SIZE, 'custom')
  check('Custom opens the three boxes right below the select, filled with Medium', (await fieldValue(b, 'CPU')) === '2' && (await fieldValue(b, 'RAM')) === '4' && (await fieldValue(b, 'Disk')) === '40')
  await b.shot('vms-create-custom.png')
  await setField(b, 'RAM', RAM_BEYOND_LIMIT_GB)
  check('a RAM above the limit is refused with the limit and Create waits', (await b.dialogText()).includes(RAM_TOO_BIG_TEXT))
  await setField(b, 'CPU', '65')
  check('a CPU above the limit is refused with the limit', (await b.dialogText()).includes('CPU must be between 1 and 64'))
  await choose(b, SIZE, 'large')
  check('picking a preset puts its numbers in and hides the boxes', (await fieldValue(b, 'CPU')) === null && !(await b.dialogText()).includes(RAM_TOO_BIG_TEXT))
  await closeWithEscape(b)
}

/** On the containers-only machine (6 GB free): Large is off with its reason in brackets, VM is off with its reason, the captions follow the choice. */
export async function disabledSizeAndRuntime(b: Browse): Promise<void> {
  await openCreate(b, `#/vms/create?machine=${CONTAINER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  const sizes = await lines(b, SIZE)
  check('with 6 GB free Large is disabled and says why in brackets; the others can be picked', JSON.stringify(sizes.map((line) => [line.value, line.disabled])) === JSON.stringify([['small', false], ['medium', false], ['large', true], ['custom', false]]) && sizes[2]?.text.endsWith('(This machine has 6 GB free)') === true, JSON.stringify(sizes))
  const runtimes = await openedMenu(b, RUNTIME)
  check('on a containers-only machine the VM row is disabled and gives its reason as the caption', runtimes.rows.length === 2 && runtimes.rows[0]?.title === 'Container' && runtimes.rows[1]?.title === 'VM' && runtimes.rows[1].disabled && runtimes.rows[1].caption === 'This machine runs containers only' && !runtimes.rows[0].disabled, JSON.stringify(runtimes.rows))
  await b.page.keyboard.press('Escape')
  const shut = await imageState(b, RUNTIME)
  check('Container is picked, and the line under the dropdown explains it', shut.trigger.startsWith('Container') && (await captionOf(b, RUNTIME)) === CONTAINER_CAPTION, shut.trigger)
  await b.shot('vms-create-containers-only.png')
  await closeWithEscape(b)
}

/** The line under the runtime select changes with the choice; a Mac adds that both run inside Apple's small VM, a Linux machine does not. */
export async function runtimeCaptions(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  await choose(b, RUNTIME, 'container')
  check('on a Mac the Container line also says both run inside Apple\'s own small VM', (await captionOf(b, RUNTIME)) === `${CONTAINER_CAPTION} ${MAC_CAPTION}`)
  await choose(b, RUNTIME, 'vm')
  check('and the VM line changes with the choice', (await captionOf(b, RUNTIME)) === `${VM_CAPTION} ${MAC_CAPTION}`)
  await closeWithEscape(b)
  await openCreate(b, `#/vms/create?machine=${CONTAINER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  check('on Linux there is no Mac sentence', (await captionOf(b, RUNTIME)) === CONTAINER_CAPTION)
  await closeWithEscape(b)
}

/** Runs `work` while counting the requests that ask the parent to create a VM; answers the count and what was asked. */
async function countingOrders(page: Page, work: () => Promise<void>): Promise<string[]> {
  const bodies: string[] = []
  const count = (request: { method: () => string; url: () => string; postData: () => string | undefined }) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === '/api/workloads') bodies.push(request.postData() ?? '')
  }
  page.on('request', count)
  try {
    await work()
  } finally {
    page.off('request', count)
  }
  return bodies
}

/** An empty name gets a generated one, five quick clicks send one order, the order carries what was picked, and the Creating row shows the generated name. */
export async function generatedNameAndOneOrder(b: Browse): Promise<void> {
  await openCreate(b, `#/vms/create?machine=${HELPER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  await choose(b, SIZE, 'small')
  await choose(b, RUNTIME, 'container')
  check('the name box is empty and shows the example', await b.run((selector) => document.querySelector<HTMLInputElement>(selector)?.value === '' && document.querySelector<HTMLInputElement>(selector)?.placeholder === 'e.g. build-box', NAME))
  const bodies = await countingOrders(b.page, async () => {
    await b.run((times) => {
      const button = [...document.querySelectorAll('dialog[open] form footer button')].find((entry) => entry.textContent?.trim() === 'Create VM')
      if (!(button instanceof HTMLButtonElement)) throw new Error('no Create VM button')
      for (let press = 0; press < times; press++) button.click()
    }, QUICK_CLICKS)
    await closeProgress(b)
  })
  check(`${QUICK_CLICKS} quick clicks on Create VM send ONE request`, bodies.length === 1, `${bodies.length}`)
  const sent: unknown = JSON.parse(bodies[0] ?? '{}')
  const body = typeof sent === 'object' && sent !== null ? Object.fromEntries(Object.entries(sent)) : {}
  check('the order has the chosen machine, kind and Small size, Blank (no bundle) and a generated name', GENERATED_NAME.test(String(body.name)) && body.kind === 'container' && body.machine === HELPER_MACHINE && body.cpu === SMALL.cpu && body.ram_mb === SMALL.ram_mb && body.disk_gb === SMALL.disk_gb && !('bundle' in body) && !('gpu_mode' in body), JSON.stringify(body))
  await b.until((name) => document.body.innerText.includes(name), { timeout: MADE_WAIT_MS }, String(body.name))
  check('the Creating row (or the new VM) shows the generated name', (await b.text()).includes(String(body.name)))
}

/** The footer is on the screen and the body scrolls in its own box. */
const footerReachable = (b: Browse) => b.run(() => {
  const footer = document.querySelector('dialog[open] form footer')?.getBoundingClientRect()
  return footer !== undefined && footer.bottom <= window.innerHeight && footer.left >= 0 && footer.right <= window.innerWidth
})

/** On a phone: everything stacks, no sideways scrolling (also with the image list and Custom open), the footer stays in reach. */
export async function onAPhoneWithSelects(b: Browse): Promise<void> {
  await b.page.setViewport(PHONE)
  await openCreate(b, `#/vms/create?machine=${CONTAINER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  check('no sideways scrolling with all the sections on a phone', await noSideScroll(b))
  check('the footer buttons are on the screen and reachable', await footerReachable(b))
  await b.shot('vms-create-containers-only-phone.png')
  await b.page.click('#vm-create-image')
  await b.shot('vms-create-image-menu-phone.png')
  check('with the image list open there is no sideways scrolling, and the list fits inside the window', (await noSideScroll(b)) && (await b.run(() => {
    const dialog = document.querySelector('dialog[open]')?.getBoundingClientRect()
    const menu = document.querySelector('dialog[open] [role=listbox]')?.getBoundingClientRect()
    return dialog !== undefined && menu !== undefined && menu.left >= dialog.left && menu.right <= dialog.right
  })))
  await b.page.keyboard.press('Escape')
  await choose(b, SIZE, 'custom')
  await b.shot('vms-create-custom-phone.png')
  check('with Custom open there is still no sideways scrolling and the footer is reachable', (await noSideScroll(b)) && (await footerReachable(b)))
  await closeWithEscape(b)

  await openCreate(b, `#/vms/create?machine=${HELPER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  await choose(b, SIZE, 'custom')
  await setField(b, 'RAM', REFUSING_RAM_GB)
  await b.click('Create VM')
  await b.page.waitForSelector('dialog[open] .aline.bad', { timeout: SHORT_WAIT_MS })
  check('a refusal shows inside the window on a phone, and the page does not scroll sideways', (await noSideScroll(b)) && (await b.dialogText()).includes('needs 512000 MB RAM'))
  await b.shot('vms-create-refusal-phone.png')
  await closeWithEscape(b)
  await b.page.setViewport(DESKTOP)
}
