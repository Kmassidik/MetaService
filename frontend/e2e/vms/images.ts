// The two image dropdowns of the Create VM window. Server image lists real server operating systems: Ubuntu Server 24.04 LTS can be picked, the other five are greyed out for good.
// Install on top lists None (the default), OpenClaw and Hermes greyed out with the catalog's reasons, and no other framework.
// A hostile title or reason stays text, a parent answer that cannot be read leaves the plain Ubuntu only with a note, the keyboard and mouse behave (arrows, Home, End, Enter, Escape closes only the list, a press outside closes it),
// a phone has no sideways scrolling, and a VM created with the defaults is asked for exactly as before (no bundle in the request).
import type { HTTPRequest, Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { FRAMEWORK, IMAGE, createFormCount, imageState, openedMenu } from '../support/createVm.ts'
import type { Browse } from '../support/page.ts'
import { XSS } from '../panel/world.ts'
import { closeWithEscape, openCreate } from './create.ts'

const SHORT_WAIT_MS = 10000
const OFFLINE_HELPER_MACHINE = 'mac-mini'
const HELPER_MACHINE = 'agent-mac'
const COMING_SOON = 'Coming soon: needs the image to be prepared on the machine'
const WAITING_FOR_PIN = 'Waiting for a pinned release and checksum'
const IMAGES_UNREADABLE = 'The list of images could not be read, so only the plain Ubuntu server is offered.'
const IMAGES_ROUTE = /\/api\/machines\/[^/]+\/images$/
const CREATE_ROUTE = /\/api\/workloads$/
const BAD_GATEWAY = 502
const OK = 200
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }
const WINDOW_TITLE = 'dialog[open] h3'
const STOCK_TITLE = 'Ubuntu Server 24.04 LTS'
const SERVER_TITLES = [STOCK_TITLE, 'Debian 12', 'Fedora Server', 'Rocky Linux', 'AlmaLinux', 'Alpine Linux']
const FRAMEWORK_TITLES = ['None — just the server', 'OpenClaw', 'Hermes']
const PREVIEW_SYSTEM_CAPTION = 'Coming soon: not tested on this machine yet'
/** None, the catalog's frameworks, and nothing else. */
const FRAMEWORK_COUNT = 3
const FRAMEWORK_COUNT_WITH_TWO_PICKABLE = 4
const FRAMEWORK_COUNT_WITH_HOSTILE = 2
const FRAMEWORK_COUNT_WITH_STOCK_ONLY = 1
const TWO_PICKABLE = {
  helper: 'answered',
  images: [
    { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null },
    { id: 'alpha', title: 'Alpha', description: 'First extra.', state: 'ready', ready: true, available: true, reason: null },
    { id: 'beta', title: 'Beta', description: 'Not yet.', state: 'planned', ready: false, available: false, reason: 'Not yet' },
    { id: 'gamma', title: 'Gamma', description: 'Second extra.', state: 'ready', ready: true, available: true, reason: null },
  ],
}

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
const dropdownCount = (b: Browse, trigger: string, count: number) => b.until((selector, wanted) => Number(document.querySelector(selector)?.getAttribute('data-count')) === wanted, { timeout: SHORT_WAIT_MS }, trigger, count)

/** Escape shuts an open list first (and only that); a second Escape closes the window. */
async function closeWindow(b: Browse): Promise<void> {
  for (const trigger of [IMAGE, FRAMEWORK]) if ((await imageState(b, trigger)).expanded) await b.page.keyboard.press('Escape')
  await closeWithEscape(b)
}

const focusIsOn = (b: Browse, trigger: string) => b.run((selector) => document.activeElement === document.querySelector(selector), trigger)
const windowStillOpen = (b: Browse) => b.run(() => document.querySelector('dialog[open]') !== null)
const pressed = async (b: Browse, trigger: string, key: Parameters<Browse['page']['keyboard']['press']>[0]) => {
  await b.page.keyboard.press(key)
  return imageState(b, trigger)
}

/** Remembers the body of every request that asks the parent to create a VM, from now on. */
export function recordCreateBodies(page: Page): string[] {
  const bodies: string[] = []
  page.on('request', (request) => {
    if (request.method() === 'POST' && CREATE_ROUTE.test(new URL(request.url()).pathname)) bodies.push(request.postData() ?? '')
  })
  return bodies
}

/** Answers the images route with this status and body while `work` runs; every other request goes on untouched. */
async function whileAnswering(b: Browse, status: number, body: unknown, work: () => Promise<void>): Promise<void> {
  const decide = (request: HTTPRequest) => {
    if (!IMAGES_ROUTE.test(new URL(request.url()).pathname)) return void request.continue()
    return void request.respond({ status, contentType: 'application/json', body: JSON.stringify(body) })
  }
  await b.page.setRequestInterception(true)
  b.page.on('request', decide)
  try {
    await work()
  } finally {
    b.page.off('request', decide)
    await b.page.setRequestInterception(false)
  }
}

export const openOn = async (b: Browse, machine: string): Promise<void> => {
  await openCreate(b, `#/vms/create?machine=${machine}`)
  await b.page.waitForSelector(IMAGE, { timeout: SHORT_WAIT_MS })
}

/** On a machine whose helper does not answer, and on one whose helper does: Server image lists only operating systems; Ubuntu can be picked, the five others never. */
export async function imageSelect(b: Browse): Promise<void> {
  for (const machine of [OFFLINE_HELPER_MACHINE, HELPER_MACHINE]) {
    await openOn(b, machine)
    await dropdownCount(b, FRAMEWORK, FRAMEWORK_COUNT)
    const shut = await imageState(b)
    check(`${machine}: the button shows Ubuntu Server 24.04 LTS with its caption, never Blank, and the list is shut`, !shut.expanded && shut.trigger.includes(STOCK_TITLE) && shut.trigger.includes('Plain Ubuntu with the usual server tools. Nothing else.') && !shut.trigger.includes('Blank') && shut.rows.length === 0, JSON.stringify(shut))
    const list = await openedMenu(b, IMAGE)
    check(`${machine}: the list is exactly the six server operating systems`, list.expanded && JSON.stringify(list.rows.map((row) => row.title)) === JSON.stringify(SERVER_TITLES), JSON.stringify(list.rows.map((row) => row.title)))
    check(`${machine}: only Ubuntu can be picked; it is selected and tagged Default`, list.rows[0]?.selected === true && list.rows[0].tag === 'Default' && !list.rows[0].disabled && list.rows.slice(1).every((row) => row.disabled && !row.selected), JSON.stringify(list.rows))
    check(`${machine}: the other five say Coming soon: not tested on this machine yet, with a COMING SOON tag`, list.rows.slice(1).every((row) => row.caption === PREVIEW_SYSTEM_CAPTION && row.tag === 'Coming soon'), JSON.stringify(list.rows))
    const wiring = await b.run((trigger) => {
      const button = document.querySelector(trigger)
      const menu = document.querySelector('dialog[open] [role=listbox]')
      return { haspopup: button?.getAttribute('aria-haspopup'), controls: button?.getAttribute('aria-controls') === menu?.id, named: menu?.getAttribute('aria-labelledby') !== null }
    }, IMAGE)
    check(`${machine}: the button has aria-haspopup=listbox and controls a listbox that has a name`, wiring.haspopup === 'listbox' && wiring.controls && wiring.named, JSON.stringify(wiring))
    await b.page.click('dialog[open] [role=option][aria-disabled=true]')
    const after = await imageState(b)
    check(`${machine}: clicking a coming-soon system selects nothing and the list stays open`, after.expanded && after.rows[0]?.selected === true && after.rows[1]?.selected === false)
    await b.page.keyboard.press('End')
    const keyed = await pressed(b, IMAGE, 'ArrowDown')
    check(`${machine}: the keyboard cannot reach a coming-soon system (the cursor stays on Ubuntu)`, keyed.rows[0]?.active === true && keyed.rows.slice(1).every((row) => !row.active), JSON.stringify(keyed.rows))
    const picked = await pressed(b, IMAGE, 'Enter')
    check(`${machine}: Enter keeps Ubuntu and shuts the list`, !picked.expanded && picked.trigger.includes(STOCK_TITLE))
    if (machine === HELPER_MACHINE) {
      await b.page.click(IMAGE)
      await b.shot('vms-create-server-menu.png')
    }
    await closeWindow(b)
  }
}

/** Install on top: None is the default, OpenClaw and Hermes are greyed out with the catalog's reasons, and no other framework is listed. */
export async function frameworkSelect(b: Browse): Promise<void> {
  for (const machine of [OFFLINE_HELPER_MACHINE, HELPER_MACHINE]) {
    await openOn(b, machine)
    await dropdownCount(b, FRAMEWORK, FRAMEWORK_COUNT)
    const shut = await imageState(b, FRAMEWORK)
    check(`${machine}: Install on top shows None — just the server`, !shut.expanded && shut.trigger.includes('None — just the server'), JSON.stringify(shut))
    const list = await openedMenu(b, FRAMEWORK)
    check(`${machine}: the list is None, OpenClaw and Hermes`, JSON.stringify(list.rows.map((row) => row.title)) === JSON.stringify(FRAMEWORK_TITLES), JSON.stringify(list.rows.map((row) => row.title)))
    const appsReady = machine === HELPER_MACHINE
    const pickable = appsReady ? 3 : 1
    check(`${machine}: None is selected and can be picked; ${appsReady ? 'OpenClaw and Hermes can be picked too' : 'every other row is disabled'}`, list.rows[0]?.selected === true && !list.rows[0].disabled && list.rows.slice(1, pickable).every((row) => !row.disabled && !row.selected) && list.rows.slice(pickable).every((row) => row.disabled && !row.selected), JSON.stringify(list.rows))
    if (appsReady) check(`${machine}: OpenClaw and Hermes carry the Installs on start tag, because the helper can install them`, list.rows[1]?.tag === 'Installs on start' && list.rows[2]?.tag === 'Installs on start', JSON.stringify(list.rows.slice(1, 3)))
    else check(`${machine}: OpenClaw and Hermes give their catalog reasons and a Coming soon tag`, list.rows[1]?.caption === COMING_SOON && list.rows[2]?.caption === WAITING_FOR_PIN && list.rows[1].tag === 'Coming soon' && list.rows[2].tag === 'Coming soon', JSON.stringify(list.rows.slice(1, 3)))
    await b.page.click('dialog[open] [role=listbox] [role=option][aria-disabled=true]')
    const after = await imageState(b, FRAMEWORK)
    check(`${machine}: clicking a disabled framework selects nothing`, after.expanded && after.rows[0]?.selected === true)
    if (machine === HELPER_MACHINE) await b.shot('vms-create-framework-menu.png')
    await closeWindow(b)
  }
}

/** The keyboard and the mouse on Install on top, against a catalog with two frameworks that can be picked and one greyed out between them. */
export async function imageMenuKeys(b: Browse): Promise<void> {
  await whileAnswering(b, OK, TWO_PICKABLE, async () => {
    await openOn(b, HELPER_MACHINE)
    await dropdownCount(b, FRAMEWORK, FRAMEWORK_COUNT_WITH_TWO_PICKABLE)
    await b.page.focus(FRAMEWORK)
    let state = await pressed(b, FRAMEWORK, 'ArrowDown')
    check('ArrowDown on the button opens the list with None under the cursor', state.expanded && state.rows[0]?.active === true, JSON.stringify(state.rows))
    state = await pressed(b, FRAMEWORK, 'ArrowDown')
    check('ArrowDown moves to the next framework', state.rows[1]?.active === true)
    state = await pressed(b, FRAMEWORK, 'ArrowDown')
    check('and skips the greyed-out one', state.rows[3]?.active === true && state.rows[2]?.active === false)
    state = await pressed(b, FRAMEWORK, 'Home')
    check('Home goes to the first row', state.rows[0]?.active === true)
    state = await pressed(b, FRAMEWORK, 'End')
    check('End goes to the last row that can be picked (the planned ones are skipped)', state.rows[3]?.active === true, JSON.stringify(state.rows.map((row) => row.active)))
    state = await pressed(b, FRAMEWORK, 'ArrowUp')
    check('ArrowUp goes back, skipping the greyed-out row', state.rows[1]?.active === true)
    state = await pressed(b, FRAMEWORK, 'Enter')
    check('Enter picks the framework, shuts the list and shows it on the button', !state.expanded && state.trigger.includes('Alpha') && state.trigger.includes('First extra.'), state.trigger)
    check('the focus is back on the button', await focusIsOn(b, FRAMEWORK))
    await b.page.keyboard.press('ArrowDown')
    state = await pressed(b, FRAMEWORK, 'Escape')
    check('Escape shuts the list but not the window', !state.expanded && (await windowStillOpen(b)) && (await createFormCount(b)).forms === 1)
    check('and the choice is kept and the focus is on the button', state.trigger.includes('Alpha') && (await focusIsOn(b, FRAMEWORK)))
    await b.page.keyboard.press('ArrowDown')
    await b.page.keyboard.press('End')
    state = await pressed(b, FRAMEWORK, ' ')
    check('Space picks the row under the cursor', !state.expanded && state.trigger.includes('Gamma'), state.trigger)
    await b.page.click(FRAMEWORK)
    check('a click on the button opens the list again, with the picked framework marked', (await imageState(b, FRAMEWORK)).rows[3]?.selected === true)
    await b.page.click(WINDOW_TITLE)
    state = await imageState(b, FRAMEWORK)
    check('a press outside the list shuts it, and the window stays', !state.expanded && (await windowStillOpen(b)))
    await b.page.click(FRAMEWORK)
    await b.page.click('dialog[open] [role=listbox] [role=option]:nth-child(2)')
    state = await imageState(b, FRAMEWORK)
    check('a click on a row picks it', !state.expanded && state.trigger.includes('Alpha'), state.trigger)
    await closeWindow(b)
  })
}

/** Another machine in the same window starts again from None, and the choice cannot be a greyed-out row. */
export async function imageFollowsTheMachine(b: Browse): Promise<void> {
  await openCreate(b)
  await b.page.waitForSelector('#vm-create-machine')
  await b.page.select('#vm-create-machine', OFFLINE_HELPER_MACHINE)
  await b.page.waitForSelector(IMAGE)
  await b.page.select('#vm-create-machine', HELPER_MACHINE)
  await dropdownCount(b, FRAMEWORK, FRAMEWORK_COUNT)
  const list = await openedMenu(b, FRAMEWORK)
  check('after another machine is picked Install on top is None again, and OpenClaw and Hermes can be picked on a machine whose helper installs them', list.trigger.includes('None — just the server') && list.rows[0]?.selected === true && list.rows[1]?.disabled === false && list.rows[2]?.disabled === false, JSON.stringify(list))
  await closeWindow(b)
}

/** An image title, description and reason that are hostile text stay text; nothing in them runs, and the greyed-out framework still cannot be picked. */
export async function hostileImageText(b: Browse): Promise<void> {
  const answer = {
    helper: 'answered',
    images: [
      { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null },
      { id: 'openclaw', title: XSS, description: XSS, state: 'planned', ready: false, available: false, reason: XSS },
    ],
  }
  await whileAnswering(b, OK, answer, async () => {
    await openOn(b, HELPER_MACHINE)
    await dropdownCount(b, FRAMEWORK, FRAMEWORK_COUNT_WITH_HOSTILE)
    const list = await openedMenu(b, FRAMEWORK)
    check('a hostile framework title and reason are written out as text', list.rows[1]?.text.includes(XSS) === true, JSON.stringify(list))
    check('and nothing in them ran or became an element', (await b.run(() => window.__xss)) === undefined && (await b.page.$('dialog[open] img[onerror]')) === null)
    check('a hostile framework is as greyed out as any other planned one', list.rows.length === FRAMEWORK_COUNT_WITH_HOSTILE && list.rows[1]?.disabled === true && list.rows[1].text.includes(XSS), JSON.stringify(list.rows))
    await closeWindow(b)
  })
}

/** A parent answer that cannot be read, or an error, leaves only the plain Ubuntu with a plain note, and Create still works with it. */
export async function imageListFails(b: Browse): Promise<void> {
  const unreadable = [{ status: BAD_GATEWAY, body: { error: { code: 'unreachable', message: 'the machine did not answer' } } }, { status: OK, body: { helper: 'answered', images: 'blank' } }]
  for (const reply of unreadable) {
    await whileAnswering(b, reply.status, reply.body, async () => {
      await openOn(b, HELPER_MACHINE)
      await b.until((note) => document.querySelector('dialog[open]')?.textContent?.includes(note) === true, { timeout: SHORT_WAIT_MS }, IMAGES_UNREADABLE)
      const server = await openedMenu(b, IMAGE)
      check(`when the list answers ${reply.status} ${JSON.stringify(reply.body).slice(0, 30)} Ubuntu is still offered and selected`, server.rows[0]?.selected === true && !server.rows[0].disabled, JSON.stringify(server.rows))
      await b.page.keyboard.press('Escape')
      const framework = await openedMenu(b, FRAMEWORK)
      check('and Install on top has None only', framework.rows.length === FRAMEWORK_COUNT_WITH_STOCK_ONLY && framework.rows[0]?.selected === true, JSON.stringify(framework.rows.map((row) => row.title)))
      await closeWindow(b)
    })
  }
}

/** The window on a phone: the open lists stay inside the window and the page does not scroll sideways. */
export async function imageOnAPhone(b: Browse): Promise<void> {
  await b.page.setViewport(PHONE)
  await openOn(b, HELPER_MACHINE)
  await dropdownCount(b, FRAMEWORK, FRAMEWORK_COUNT)
  for (const trigger of [IMAGE, FRAMEWORK]) {
    const list = await openedMenu(b, trigger)
    check(`with ${trigger} open the window has no sideways scrolling on a phone`, list.expanded && (await noSideScroll(b)))
    check(`the ${trigger} list is inside the window on a phone`, await b.run(() => {
      const dialog = document.querySelector('dialog[open]')?.getBoundingClientRect()
      const menu = document.querySelector('dialog[open] [role=listbox]')?.getBoundingClientRect()
      return dialog !== undefined && menu !== undefined && menu.left >= dialog.left && menu.right <= dialog.right && menu.width > 200
    }))
    await b.shot(trigger === IMAGE ? 'vms-create-server-menu-phone.png' : 'vms-create-framework-menu-phone.png')
    await b.page.keyboard.press('Escape')
  }
  await closeWindow(b)
  await b.page.setViewport(DESKTOP)
}

/** Everything that asked the parent to create a VM with the defaults was exactly as before images existed: no bundle, no image. */
export function createWithDefaultsIsAsBefore(bodies: string[]): void {
  check('a create request was recorded', bodies.length > 0, `${bodies.length}`)
  const parsed = bodies.map((body): unknown => JSON.parse(body))
  check('with the defaults the request carries no bundle and never an image name', parsed.every((body) => typeof body === 'object' && body !== null && !('bundle' in body) && !('image' in body)), bodies.join(' | '))
}
