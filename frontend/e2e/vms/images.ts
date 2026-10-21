// The Image choice in the Create VM window: Blank selectable and OpenClaw and Hermes disabled with their reasons (on a machine whose helper answers and on one that does not),
// an image title and reason that are hostile text stay text, a parent answer that cannot be read leaves Blank only with a plain note, a phone has no sideways scrolling,
// and a VM created with Blank is asked for exactly as before (no bundle in the request).
import type { HTTPRequest, Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { XSS } from '../panel/world.ts'
import { closeWithEscape, openCreate } from './create.ts'

const SHORT_WAIT_MS = 10000
const IMAGE = '#vm-create-image'
const PICKER = '#vm-create-machine'
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

interface Option { value: string; text: string; disabled: boolean; selected: boolean }

const options = (b: Browse): Promise<Option[]> =>
  b.page.$$eval(`${IMAGE} option`, (list) => list.flatMap((option) => (option instanceof HTMLOptionElement ? [{ value: option.value, text: option.textContent?.trim() ?? '', disabled: option.disabled, selected: option.selected }] : [])))

const summary = (list: Option[]): string[] => list.map((option) => `${option.value}:${option.disabled ? 'off' : 'on'}${option.selected ? ':picked' : ''}`)

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

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

const imageAnswered = (b: Browse) => b.until(() => document.querySelectorAll('#vm-create-image option').length > 0, { timeout: SHORT_WAIT_MS })

/** On a machine whose helper does not answer, and on one whose helper does: Blank is picked and OpenClaw and Hermes are disabled with their reasons. */
export async function imageSelect(b: Browse): Promise<void> {
  for (const machine of [OFFLINE_HELPER_MACHINE, HELPER_MACHINE]) {
    await openOn(b, machine)
    await b.until(() => document.querySelectorAll('#vm-create-image option').length === 3, { timeout: SHORT_WAIT_MS })
    const list = await options(b)
    check(`${machine}: Blank is picked and selectable, OpenClaw and Hermes are shown disabled`, JSON.stringify(summary(list)) === JSON.stringify(['blank:on:picked', 'openclaw:off', 'hermes:off']), JSON.stringify(summary(list)))
    check(`${machine}: the options say what they are`, list[0]?.text === 'Blank (plain Ubuntu)' && list[1]?.text === 'OpenClaw (not available yet)' && list[2]?.text === 'Hermes (not available yet)', JSON.stringify(list.map((option) => option.text)))
    const text = await b.dialogText()
    check(`${machine}: each disabled image says why, in plain words, under the select`, text.includes(`OpenClaw - ${COMING_SOON}`) && text.includes(`Hermes - ${WAITING_FOR_PIN}`))
    check(`${machine}: the picked image's description is shown`, text.includes('Ubuntu 24.04 with the usual server tools. Nothing else.'))
    check(`${machine}: the Image select has a label`, await b.run((selector) => document.querySelector<HTMLSelectElement>(selector)?.labels?.length === 1, IMAGE))
    if (machine === HELPER_MACHINE) await b.shot('vms-create-image-desktop.png')
    await closeWithEscape(b)
  }
}

/** Another machine in the same window starts again from Blank, and the choice cannot be a disabled image. */
export async function imageFollowsTheMachine(b: Browse): Promise<void> {
  await openCreate(b)
  await b.page.waitForSelector(PICKER)
  await b.page.select(PICKER, OFFLINE_HELPER_MACHINE)
  await b.page.waitForSelector(IMAGE)
  await imageAnswered(b)
  await b.page.select(PICKER, HELPER_MACHINE)
  await b.until(() => document.querySelectorAll('#vm-create-image option').length === 3, { timeout: SHORT_WAIT_MS })
  check('after another machine is picked the image is Blank again', JSON.stringify(summary(await options(b))) === JSON.stringify(['blank:on:picked', 'openclaw:off', 'hermes:off']))
  await closeWithEscape(b)
}

/** An image title, description and reason that are hostile text stay text; nothing in them runs, and the disabled image still cannot be picked. */
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
    await b.until(() => document.querySelectorAll('#vm-create-image option').length === 2, { timeout: SHORT_WAIT_MS })
    const text = await b.dialogText()
    check('a hostile image title and reason are written out as text', text.includes(`${XSS} - ${XSS}`))
    check('and nothing in them ran or became an element', (await b.run(() => window.__xss)) === undefined && (await b.page.$('dialog[open] img')) === null)
    check('a hostile image is as disabled as any other planned one', JSON.stringify(summary(await options(b))) === JSON.stringify(['blank:on:picked', 'openclaw:off']))
    await closeWithEscape(b)
  })
}

/** A parent answer that cannot be read, or an error, leaves only Blank with a plain note, and Create still works with it. */
export async function imageListFails(b: Browse): Promise<void> {
  const unreadable = [{ status: BAD_GATEWAY, body: { error: { code: 'unreachable', message: 'the machine did not answer' } } }, { status: OK, body: { helper: 'answered', images: 'blank' } }]
  for (const reply of unreadable) {
    await whileAnswering(b, reply.status, reply.body, async () => {
      await openOn(b, HELPER_MACHINE)
      await b.until((note) => document.querySelector('dialog[open]')?.textContent?.includes(note) === true, { timeout: SHORT_WAIT_MS }, IMAGES_UNREADABLE)
      check(`when the list answers ${reply.status} ${JSON.stringify(reply.body).slice(0, 30)} only Blank is offered`, JSON.stringify(summary(await options(b))) === JSON.stringify(['blank:on:picked']))
      await closeWithEscape(b)
    })
  }
}

/** The window on a phone: no sideways scrolling, the whole window on the screen. */
export async function imageOnAPhone(b: Browse): Promise<void> {
  await b.page.setViewport(PHONE)
  await openOn(b, HELPER_MACHINE)
  await b.until(() => document.querySelectorAll('#vm-create-image option').length === 3, { timeout: SHORT_WAIT_MS })
  check('with the Image select the window has no sideways scrolling on a phone', await noSideScroll(b))
  check('the Image select and its lines stay inside the window on a phone', await b.run(() => {
    const dialog = document.querySelector('dialog[open]')?.getBoundingClientRect()
    const select = document.querySelector('#vm-create-image')?.getBoundingClientRect()
    return dialog !== undefined && select !== undefined && select.left >= dialog.left && select.right <= dialog.right && dialog.right <= window.innerWidth
  }))
  await b.shot('vms-create-image-phone.png')
  await closeWithEscape(b)
  await b.page.setViewport(DESKTOP)
}

/** Everything that asked the parent to create a VM with Blank picked was exactly as before images existed: no bundle, no image. */
export function createWithBlankIsAsBefore(bodies: string[]): void {
  check('a create request was recorded', bodies.length > 0, `${bodies.length}`)
  const parsed = bodies.map((body): unknown => JSON.parse(body))
  check('with Blank the request carries no bundle and never an image name', parsed.every((body) => typeof body === 'object' && body !== null && !('bundle' in body) && !('image' in body)), bodies.join(' | '))
}
