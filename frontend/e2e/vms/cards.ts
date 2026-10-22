// The Create VM window is ONE window for every way in, its cards are radio groups, Custom opens the boxes, an empty name gets a generated one, five quick clicks send one order,
// the order carries what was picked, and on a phone nothing scrolls sideways while the footer stays in reach.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { CREATE_FORM, IMAGE_GROUP, NAME, RUNTIME_GROUP, SIZE_GROUP, createFormCount, fieldValue, imageListArrived, pickCard, pickedCard, setField } from '../support/createVm.ts'
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

/** Each card group is a radio group with a name, and the arrow keys and Space move the choice; the greyed-out cards are skipped. */
export async function cardsAreRadioGroups(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  const groups = await b.page.$$eval('dialog[open] [role=radiogroup]', (list) => list.map((group) => document.getElementById(group.getAttribute('aria-labelledby') ?? '')?.textContent ?? ''))
  check('there are three radio groups, each named by its label', JSON.stringify(groups) === JSON.stringify(['Image', 'Size', 'Runtime']), JSON.stringify(groups))
  await pickCard(b, SIZE_GROUP, 'small')
  check('clicking a size card picks it', (await pickedCard(b, SIZE_GROUP)) === 'small')
  await b.page.focus(`dialog[open] input[name="${SIZE_GROUP}"]:checked`)
  await b.page.keyboard.press('ArrowRight')
  check('the right arrow moves the choice to the next size', (await pickedCard(b, SIZE_GROUP)) === 'medium')
  await b.page.keyboard.press('ArrowRight')
  await b.page.keyboard.press('ArrowRight')
  check('and on to Custom, which opens the three boxes', (await pickedCard(b, SIZE_GROUP)) === 'custom' && (await fieldValue(b, 'CPU')) === '4')
  await b.page.keyboard.press('ArrowLeft')
  await b.page.keyboard.press('ArrowLeft')
  await b.page.keyboard.press('ArrowLeft')
  check('the left arrow goes back to Small', (await pickedCard(b, SIZE_GROUP)) === 'small')
  await b.page.focus(`dialog[open] input[name="${SIZE_GROUP}"][value=large]`)
  await b.page.keyboard.press('Space')
  check('Space picks the card that has the focus', (await pickedCard(b, SIZE_GROUP)) === 'large')
  await b.page.focus(`dialog[open] input[name="${IMAGE_GROUP}"]:checked`)
  await b.page.keyboard.press('ArrowRight')
  check('the arrow keys skip the greyed-out images: Blank stays picked', (await pickedCard(b, IMAGE_GROUP)) === 'blank')
  await b.page.focus(`dialog[open] input[name="${RUNTIME_GROUP}"]:checked`)
  await b.page.keyboard.press('ArrowLeft')
  check('the arrow keys move between Container and VM', (await pickedCard(b, RUNTIME_GROUP)) === 'container')
  const focusRing = await b.run((group) => {
    const card = document.querySelector(`dialog[open] input[name="${group}"]:checked`)?.closest('label')
    return card !== null && card !== undefined && getComputedStyle(card).outlineStyle !== 'none' && getComputedStyle(card).outlineWidth !== '0px'
  }, RUNTIME_GROUP)
  check('the card that has the keyboard focus shows a focus ring', focusRing)
  await closeWithEscape(b)
}

/** Custom opens CPU, RAM and Disk with the usual limits and messages; a preset hides them again. */
export async function customBoxes(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  await b.shot('vms-create-medium.png')
  check('the three boxes are not there while a preset is picked', (await fieldValue(b, 'CPU')) === null)
  await pickCard(b, SIZE_GROUP, 'custom')
  await setField(b, 'RAM', RAM_BEYOND_LIMIT_GB)
  check('a RAM above the limit is refused with the limit and Create waits', (await b.dialogText()).includes(RAM_TOO_BIG_TEXT))
  await pickCard(b, SIZE_GROUP, 'large')
  check('picking a preset puts its numbers in and hides the boxes', (await fieldValue(b, 'CPU')) === null && !(await b.dialogText()).includes(RAM_TOO_BIG_TEXT))
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
  await pickCard(b, SIZE_GROUP, 'small')
  await pickCard(b, RUNTIME_GROUP, 'container')
  check('the name box is empty and shows the example', (await b.run((selector) => document.querySelector<HTMLInputElement>(selector)?.value === '' && document.querySelector<HTMLInputElement>(selector)?.placeholder === 'e.g. build-box', NAME)))
  const bodies = await countingOrders(b.page, async () => {
    await b.run((times) => {
      const button = [...document.querySelectorAll('dialog[open] form footer button')].find((entry) => entry.textContent?.trim() === 'Create VM')
      if (!(button instanceof HTMLButtonElement)) throw new Error('no Create VM button')
      for (let press = 0; press < times; press++) button.click()
    }, QUICK_CLICKS)
    await closed(b)
  })
  check(`${QUICK_CLICKS} quick clicks on Create VM send ONE request`, bodies.length === 1, `${bodies.length}`)
  const sent: unknown = JSON.parse(bodies[0] ?? '{}')
  const body = typeof sent === 'object' && sent !== null ? Object.fromEntries(Object.entries(sent)) : {}
  check('the order has the chosen machine, kind and Small size, Blank (no bundle) and a generated name', GENERATED_NAME.test(String(body.name)) && body.kind === 'container' && body.machine === HELPER_MACHINE && body.cpu === SMALL.cpu && body.ram_mb === SMALL.ram_mb && body.disk_gb === SMALL.disk_gb && !('bundle' in body), JSON.stringify(body))
  await b.until((name) => document.body.innerText.includes(name), { timeout: MADE_WAIT_MS }, String(body.name))
  check('the Creating row (or the new VM) shows the generated name', (await b.text()).includes(String(body.name)))
}

/** On a phone: image cards one column, size cards two, no sideways scrolling, and the footer stays in reach while the body scrolls. */
export async function onAPhoneWithCards(b: Browse): Promise<void> {
  await b.page.setViewport(PHONE)
  await openCreate(b, `#/vms/create?machine=${CONTAINER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  check('no sideways scrolling with all three card rows on a phone', await noSideScroll(b))
  const columns = await b.run((group) => {
    const lefts = (name: string) => new Set([...document.querySelectorAll(`dialog[open] input[name="${name}"]`)].map((input) => Math.round(input.closest('label')?.getBoundingClientRect().left ?? -1))).size
    return { size: lefts(group) }
  }, SIZE_GROUP)
  check('the four size cards sit in two columns', columns.size === 2, JSON.stringify(columns))
  check('the footer buttons are on the screen and reachable', await b.run(() => {
    const footer = document.querySelector('dialog[open] form footer')?.getBoundingClientRect()
    return footer !== undefined && footer.bottom <= window.innerHeight && footer.left >= 0 && footer.right <= window.innerWidth
  }))
  await b.shot('vms-create-containers-only-phone.png')
  await pickCard(b, SIZE_GROUP, 'custom')
  await b.shot('vms-create-custom-phone.png')
  check('with Custom open there is still no sideways scrolling', await noSideScroll(b))
  await closeWithEscape(b)

  await openCreate(b, `#/vms/create?machine=${HELPER_MACHINE}`)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  await pickCard(b, SIZE_GROUP, 'custom')
  await setField(b, 'RAM', REFUSING_RAM_GB)
  await b.click('Create VM')
  await b.page.waitForSelector('dialog[open] .aline.bad', { timeout: SHORT_WAIT_MS })
  check('a refusal shows inside the window on a phone, and the page does not scroll sideways', (await noSideScroll(b)) && (await b.dialogText()).includes('needs 512000 MB RAM'))
  await b.shot('vms-create-refusal-phone.png')
  await closeWithEscape(b)
  await b.page.setViewport(DESKTOP)
}

