// The Server image dropdown in the Create VM window: Blank selectable and OpenClaw and Hermes greyed out with their reasons and a tag (on a machine whose helper answers and on one that does not),
// an image title and reason that are hostile text stay text, a parent answer that cannot be read leaves Blank only with a plain note, the keyboard and mouse behave (arrows, Home, End, Enter, Escape closes only the list, a press outside closes it), a phone has no sideways scrolling,
// and a VM created with Blank is asked for exactly as before (no bundle in the request).
import type { HTTPRequest, Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { IMAGE, NAME, createFormCount, imageState } from '../support/createVm.ts'
import type { Browse } from '../support/page.ts'
import { XSS } from '../panel/world.ts'
import { closeWithEscape, openCreate } from './create.ts'

const SHORT_WAIT_MS = 10000
const OFFLINE_HELPER_MACHINE = 'mac-mini'
const HELPER_MACHINE = 'agent-mac'
const COMING_SOON = 'Coming soon: needs the image to be prepared on the machine'
const WAITING_FOR_PIN = 'Waiting for a pinned release and checksum'
const IMAGES_UNREADABLE = 'The list of images could not be read, so only Blank is offered.'
const IMAGES_ROUTE = /\/api\/machines\/[^/]+\/images$/
const CREATE_ROUTE = /\/api\/workloads$/
const BAD_GATEWAY = 502
const OK = 200
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
const imageCount = (b: Browse, count: number) => b.until((wanted) => Number(document.querySelector('[data-images]')?.getAttribute('data-images')) === wanted, { timeout: SHORT_WAIT_MS }, count)
const opened = async (b: Browse) => {
  await b.page.click(IMAGE)
  return imageState(b)
}
/** Escape shuts the image list first (and only that); a second Escape closes the window. */
async function closeWindow(b: Browse): Promise<void> {
  if ((await imageState(b)).expanded) await b.page.keyboard.press('Escape')
  await closeWithEscape(b)
}

const focusIsOnButton = (b: Browse) => b.run((trigger) => document.activeElement === document.querySelector(trigger), IMAGE)
const windowStillOpen = (b: Browse) => b.run(() => document.querySelector('dialog[open]') !== null)
const pressed = async (b: Browse, key: Parameters<Browse['page']['keyboard']['press']>[0]) => {
  await b.page.keyboard.press(key)
  return imageState(b)
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

const openOn = async (b: Browse, machine: string): Promise<void> => {
  await openCreate(b, `#/vms/create?machine=${machine}`)
  await b.page.waitForSelector(IMAGE, { timeout: SHORT_WAIT_MS })
}

const ALL_THREE_TEXT = ['Blank (plain Ubuntu)', 'OpenClaw', 'Hermes']
const TWO_PICKABLE = {
  helper: 'answered',
  images: [
    { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null },
    { id: 'alpha', title: 'Alpha', description: 'First extra.', state: 'ready', ready: true, available: true, reason: null },
    { id: 'beta', title: 'Beta', description: 'Not yet.', state: 'planned', ready: false, available: false, reason: 'Not yet' },
    { id: 'gamma', title: 'Gamma', description: 'Second extra.', state: 'ready', ready: true, available: true, reason: null },
  ],
}
const IMAGE_COUNT_WITH_TWO_PICKABLE = 4

/** On a machine whose helper does not answer, and on one whose helper does: the list has Blank (Default) and OpenClaw and Hermes greyed out with their reasons and a tag. */
export async function imageSelect(b: Browse): Promise<void> {
  for (const machine of [OFFLINE_HELPER_MACHINE, HELPER_MACHINE]) {
    await openOn(b, machine)
    await imageCount(b, 3)
    const shut = await imageState(b)
    check(`${machine}: the button shows Blank, with its caption, and the list is shut`, !shut.expanded && shut.trigger.includes('Blank (plain Ubuntu)') && shut.trigger.includes('Ubuntu 24.04 with the usual server tools. Nothing else.') && shut.rows.length === 0, JSON.stringify(shut))
    const list = await opened(b)
    check(`${machine}: the list opens with one row for each image of the catalog`, list.expanded && list.rows.length === 3 && ALL_THREE_TEXT.every((title, at) => list.rows[at]?.text.includes(title)), JSON.stringify(list.rows))
    check(`${machine}: Blank is selected and tagged Default; OpenClaw and Hermes are disabled`, list.rows[0]?.selected === true && list.rows[0].tag === 'Default' && list.rows[1]?.disabled === true && list.rows[2]?.disabled === true, JSON.stringify(list.rows))
    check(`${machine}: each greyed-out image gives its reason as its caption and a Coming soon tag`, list.rows[1]?.text.includes(COMING_SOON) === true && list.rows[2]?.text.includes(WAITING_FOR_PIN) === true && list.rows[1].tag === 'Coming soon' && list.rows[2].tag === 'Coming soon', JSON.stringify(list.rows))
    const wiring = await b.run((trigger) => {
      const button = document.querySelector(trigger)
      const menu = document.querySelector('dialog[open] [role=listbox]')
      return { haspopup: button?.getAttribute('aria-haspopup'), controls: button?.getAttribute('aria-controls') === menu?.id, named: menu?.getAttribute('aria-labelledby') !== null }
    }, IMAGE)
    check(`${machine}: the button has aria-haspopup=listbox and controls a listbox that has a name`, wiring.haspopup === 'listbox' && wiring.controls && wiring.named, JSON.stringify(wiring))
    await b.page.click('dialog[open] [role=option][aria-disabled=true]')
    const after = await imageState(b)
    check(`${machine}: clicking a disabled image selects nothing and the list stays open`, after.expanded && after.rows[0]?.selected === true && after.rows[1]?.selected === false)
    if (machine === HELPER_MACHINE) await b.shot('vms-create-image-menu.png')
    await closeWindow(b)
  }
}

/** The keyboard and the mouse on the list, against a catalog with two images that can be picked and one greyed out between them. */
export async function imageMenuKeys(b: Browse): Promise<void> {
  await whileAnswering(b, OK, TWO_PICKABLE, async () => {
    await openOn(b, HELPER_MACHINE)
    await imageCount(b, IMAGE_COUNT_WITH_TWO_PICKABLE)
    await b.page.focus(IMAGE)
    let state = await pressed(b, 'ArrowDown')
    check('ArrowDown on the button opens the list with Blank under the cursor', state.expanded && state.rows[0]?.active === true, JSON.stringify(state.rows))
    state = await pressed(b, 'ArrowDown')
    check('ArrowDown moves to the next image', state.rows[1]?.active === true)
    state = await pressed(b, 'ArrowDown')
    check('and skips the greyed-out one', state.rows[3]?.active === true && state.rows[2]?.active === false)
    state = await pressed(b, 'Home')
    check('Home goes to the first image', state.rows[0]?.active === true)
    state = await pressed(b, 'End')
    check('End goes to the last image that can be picked', state.rows[3]?.active === true)
    state = await pressed(b, 'ArrowUp')
    check('ArrowUp goes back, skipping the greyed-out image', state.rows[1]?.active === true)
    state = await pressed(b, 'Enter')
    check('Enter picks the image, shuts the list and shows it on the button', !state.expanded && state.trigger.includes('Alpha') && state.trigger.includes('First extra.'), state.trigger)
    check('the focus is back on the button', await focusIsOnButton(b))
    await b.page.keyboard.press('ArrowDown')
    state = await pressed(b, 'Escape')
    check('Escape shuts the list but not the window', !state.expanded && (await windowStillOpen(b)) && (await createFormCount(b)).forms === 1)
    check('and the choice is kept and the focus is on the button', state.trigger.includes('Alpha') && (await focusIsOnButton(b)))
    await b.page.keyboard.press('ArrowDown')
    await b.page.keyboard.press('End')
    state = await pressed(b, ' ')
    check('Space picks the image under the cursor', !state.expanded && state.trigger.includes('Gamma'), state.trigger)
    await b.page.click(IMAGE)
    check('a click on the button opens the list again, with the picked image marked', (await imageState(b)).rows[3]?.selected === true)
    await b.page.click(NAME)
    state = await imageState(b)
    check('a press outside the list shuts it, and the window stays', !state.expanded && (await windowStillOpen(b)))
    await b.page.click(IMAGE)
    await b.page.click('dialog[open] [role=option]:nth-child(2)')
    state = await imageState(b)
    check('a click on a row picks it', !state.expanded && state.trigger.includes('Alpha'), state.trigger)
    await closeWindow(b)
  })
}

/** Another machine in the same window starts again from Blank, and the choice cannot be a greyed-out image. */
export async function imageFollowsTheMachine(b: Browse): Promise<void> {
  await openCreate(b)
  await b.page.waitForSelector('#vm-create-machine')
  await b.page.select('#vm-create-machine', OFFLINE_HELPER_MACHINE)
  await b.page.waitForSelector(IMAGE)
  await b.page.select('#vm-create-machine', HELPER_MACHINE)
  await imageCount(b, 3)
  const list = await opened(b)
  check('after another machine is picked the image is Blank again and the other two are still greyed out', list.trigger.includes('Blank (plain Ubuntu)') && list.rows[0]?.selected === true && list.rows[1]?.disabled === true && list.rows[2]?.disabled === true, JSON.stringify(list))
  await closeWindow(b)
}

/** An image title, description and reason that are hostile text stay text; nothing in them runs, and the greyed-out image still cannot be picked. */
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
    await imageCount(b, 2)
    const list = await opened(b)
    check('a hostile image title and reason are written out as text', list.rows[1]?.text.includes(XSS) === true, JSON.stringify(list))
    check('and nothing in them ran or became an element', (await b.run(() => window.__xss)) === undefined && (await b.page.$('dialog[open] img')) === null)
    check('a hostile image is as greyed out as any other planned one, and written out as text in the list', list.rows.length === 2 && list.rows[1]?.disabled === true && list.rows[1].text.includes(XSS) && (await b.run(() => window.__xss)) === undefined, JSON.stringify(list.rows))
    await closeWindow(b)
  })
}

/** A parent answer that cannot be read, or an error, leaves only Blank with a plain note, and Create still works with it. */
export async function imageListFails(b: Browse): Promise<void> {
  const unreadable = [{ status: BAD_GATEWAY, body: { error: { code: 'unreachable', message: 'the machine did not answer' } } }, { status: OK, body: { helper: 'answered', images: 'blank' } }]
  for (const reply of unreadable) {
    await whileAnswering(b, reply.status, reply.body, async () => {
      await openOn(b, HELPER_MACHINE)
      await b.until((note) => document.querySelector('dialog[open]')?.textContent?.includes(note) === true, { timeout: SHORT_WAIT_MS }, IMAGES_UNREADABLE)
      const list = await opened(b)
      check(`when the list answers ${reply.status} ${JSON.stringify(reply.body).slice(0, 30)} only Blank is offered`, list.rows.length === 1 && list.rows[0]?.selected === true, JSON.stringify(list.rows))
      await closeWindow(b)
    })
  }
}

/** The window on a phone: the open list stays inside the window and the page does not scroll sideways. */
export async function imageOnAPhone(b: Browse): Promise<void> {
  await b.page.setViewport(PHONE)
  await openOn(b, HELPER_MACHINE)
  await imageCount(b, 3)
  const list = await opened(b)
  check('with the image list open the window has no sideways scrolling on a phone', list.expanded && (await noSideScroll(b)))
  check('the list is inside the window on a phone', await b.run(() => {
    const dialog = document.querySelector('dialog[open]')?.getBoundingClientRect()
    const menu = document.querySelector('dialog[open] [role=listbox]')?.getBoundingClientRect()
    return dialog !== undefined && menu !== undefined && menu.left >= dialog.left && menu.right <= dialog.right && menu.width > 200
  }))
  await b.shot('vms-create-image-phone.png')
  await closeWindow(b)
  await b.page.setViewport(DESKTOP)
}

/** Everything that asked the parent to create a VM with Blank picked was exactly as before images existed: no bundle, no image. */
export function createWithBlankIsAsBefore(bodies: string[]): void {
  check('a create request was recorded', bodies.length > 0, `${bodies.length}`)
  const parsed = bodies.map((body): unknown => JSON.parse(body))
  check('with Blank the request carries no bundle and never an image name', parsed.every((body) => typeof body === 'object' && body !== null && !('bundle' in body) && !('image' in body)), bodies.join(' | '))
}
