// What the three rich dropdowns of the Create VM window look like and how they behave: every logo is a bundled picture that really rendered (no letter, no dark box behind it, no request to another site),
// the runtime dropdown describes each kind and its line follows the choice, and the keyboard works the same in all of them. The screenshots (desktop and phone) are taken here.
import type { Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { FRAMEWORK, IMAGE, RUNTIME, captionOf, imageState, openedMenu } from '../support/createVm.ts'
import type { Browse } from '../support/page.ts'
import { closeWithEscape, openCreate } from './create.ts'

const SHORT_WAIT_MS = 10000
const MAC_MACHINE = 'mac-mini'
const HELPER_MACHINE = 'agent-mac'
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }
const LOGO_SIZE_PX = 28
const TRANSPARENT = 'rgba(0, 0, 0, 0)'
const FRAMEWORK_ROWS_WITH_LOGOS = 2
const SERVER_ROWS_WITH_LOGOS = 6
const CONTAINER_TEXT = "Fast stop and wake. Shares the machine's core, so it starts in seconds and uses little memory. Best for agents and apps."
const VM_TEXT = 'A full computer with its own core: a stronger wall, slower start, more memory. Needs virtualization on the machine.'
const MAC_SENTENCE = "On a Mac both run inside Apple's own small VM."

/** Remembers every picture the page asks for from now on: which came from another site, and which failed. */
export function watchPictures(page: Page, ownOrigin: string): { elsewhere: string[]; failed: string[] } {
  const seen = { elsewhere: [] as string[], failed: [] as string[] }
  page.on('request', (request) => {
    const url = request.url()
    if (request.resourceType() === 'image' && !url.startsWith('data:') && !url.startsWith(ownOrigin)) seen.elsewhere.push(url)
  })
  page.on('requestfailed', (request) => request.resourceType() === 'image' && seen.failed.push(request.url()))
  return seen
}

export function noPictureFromElsewhere(seen: { elsewhere: string[]; failed: string[] }): void {
  check('every picture in the window was a bundled file or data: none came from another site and none failed', seen.elsewhere.length === 0 && seen.failed.length === 0, JSON.stringify(seen))
}

interface BadgeReport {
  kind: string
  letters: string
  background: string
  box: number
  loaded: boolean
  alt: string | null
  fit: string
  hidden: string | null
}

const badgeReports = (b: Browse, menu: string): Promise<BadgeReport[]> =>
  b.run((selector) => [...document.querySelectorAll(`dialog[open] ${selector} [role=option] .badge`)].map((badge) => {
    const img = badge.querySelector('img')
    return {
      kind: badge.getAttribute('data-badge') ?? '',
      letters: (badge.textContent ?? '').trim(),
      background: getComputedStyle(badge).backgroundColor,
      box: Math.round(img?.getBoundingClientRect().height ?? 0),
      loaded: img !== null && img.complete && img.naturalWidth > 0,
      alt: img?.getAttribute('alt') ?? null,
      fit: img ? getComputedStyle(img).objectFit : '',
      hidden: badge.getAttribute('aria-hidden'),
    }
  }), menu)

const picturesLoaded = (b: Browse) => b.until(() => [...document.querySelectorAll('dialog[open] [role=listbox] img')].every((img) => img instanceof HTMLImageElement && img.complete), { timeout: SHORT_WAIT_MS })

/** The logos in the server and framework lists really rendered as plain pictures; the None row has an outline picture and no dark box. */
export async function logosRendered(b: Browse): Promise<void> {
  await openCreate(b, `#/vms/create?machine=${HELPER_MACHINE}`)
  await b.page.waitForSelector(IMAGE, { timeout: SHORT_WAIT_MS })
  await b.until((trigger) => Number(document.querySelector(trigger)?.getAttribute('data-count')) === 3, { timeout: SHORT_WAIT_MS }, FRAMEWORK)
  await openedMenu(b, IMAGE)
  await picturesLoaded(b)
  const server = await badgeReports(b, '#vm-create-image-menu')
  check('every server operating system row shows a loaded logo picture, 28 px, decorative, contained', server.length === SERVER_ROWS_WITH_LOGOS && server.every((badge) => badge.kind === 'logo' && badge.loaded && badge.box === LOGO_SIZE_PX && badge.alt === '' && badge.hidden === 'true' && badge.fit === 'contain'), JSON.stringify(server))
  check('a logo badge has no letter and no coloured or dark box behind it', server.every((badge) => badge.letters === '' && badge.background === TRANSPARENT), JSON.stringify(server))
  await b.page.keyboard.press('Escape')
  await openedMenu(b, FRAMEWORK)
  await picturesLoaded(b)
  const framework = await badgeReports(b, '#vm-create-framework-menu')
  const withLogo = framework.slice(1)
  check('OpenClaw and Hermes each show a loaded logo', withLogo.length === FRAMEWORK_ROWS_WITH_LOGOS && withLogo.every((badge) => badge.kind === 'logo' && badge.loaded && badge.letters === '' && badge.background === TRANSPARENT), JSON.stringify(withLogo))
  check('None has a small outline icon, no letter and no dark box', framework[0]?.kind === 'none' && framework[0].letters === '' && framework[0].background === TRANSPARENT, JSON.stringify(framework[0]))
  const grey = await b.run(() => [...document.querySelectorAll('dialog[open] #vm-create-framework-menu [role=option][aria-disabled=true] img')].every((img) => getComputedStyle(img).filter.includes('grayscale') && Number(getComputedStyle(img).opacity) < 1))
  check('the logos of rows that cannot be picked are greyed (grayscale and faded)', grey)
  await b.page.keyboard.press('Escape')
  await closeWithEscape(b)
}

/** Each runtime row has a title, a description and a tag; the line under the closed dropdown follows the choice and keeps the Mac sentence on a Mac. */
export async function runtimeDropdown(b: Browse): Promise<void> {
  await openCreate(b, `#/vms/create?machine=${MAC_MACHINE}`)
  await b.page.waitForSelector(RUNTIME)
  const list = await openedMenu(b, RUNTIME)
  check('the runtime list has Container (Recommended) and VM, each with its description', list.rows.length === 2 && list.rows[0]?.title === 'Container' && list.rows[0].tag === 'Recommended' && list.rows[0].caption === CONTAINER_TEXT && list.rows[1]?.title === 'VM' && list.rows[1].caption === VM_TEXT && list.rows[1].tag === '', JSON.stringify(list.rows))
  const icons = await b.run(() => [...document.querySelectorAll('dialog[open] #vm-create-runtime-menu .badge')].map((badge) => [badge.getAttribute('data-badge'), badge.querySelector('svg') !== null, badge.querySelector('img') === null]))
  check('the rows have a simple outline icon (a box and a screen), no logo', JSON.stringify(icons) === JSON.stringify([['container', true, true], ['vm', true, true]]), JSON.stringify(icons))
  await b.shot('vms-create-runtime-menu.png')
  await b.page.keyboard.press('Escape')
  await b.page.focus(RUNTIME)
  let state = await pressed(b, 'ArrowDown')
  check('ArrowDown on the closed dropdown opens it with the picked row under the cursor', state.expanded && state.rows.some((row) => row.active && row.selected), JSON.stringify(state.rows))
  state = await pressed(b, 'Home')
  check('Home goes to Container', state.rows[0]?.active === true)
  state = await pressed(b, 'End')
  check('End goes to VM', state.rows[1]?.active === true)
  state = await pressed(b, 'Enter')
  check('Enter picks VM, shuts the list, and the line under the dropdown changes', !state.expanded && state.trigger.startsWith('VM') && (await captionOf(b, RUNTIME)) === `${VM_TEXT} ${MAC_SENTENCE}`, state.trigger)
  await b.page.keyboard.press('ArrowDown')
  await b.page.keyboard.press('Home')
  state = await pressed(b, 'Escape')
  check('Escape shuts the list but not the window, and keeps VM', !state.expanded && state.trigger.startsWith('VM') && (await b.run(() => document.querySelector('dialog[open]') !== null)))
  await openedMenu(b, RUNTIME)
  await b.page.click('dialog[open] #vm-create-runtime-menu [role=option][data-value=container]')
  state = await imageState(b, RUNTIME)
  check('a click on Container picks it and the line under the dropdown follows', state.trigger.startsWith('Container') && (await captionOf(b, RUNTIME)) === `${CONTAINER_TEXT} ${MAC_SENTENCE}`, state.trigger)
  await closeWithEscape(b)
}

const pressed = async (b: Browse, key: Parameters<Browse['page']['keyboard']['press']>[0]) => {
  await b.page.keyboard.press(key)
  return imageState(b, RUNTIME)
}

/** Pictures of the window on a desktop and on a phone: the default state and each of the three lists open. */
export async function dropdownPictures(b: Browse): Promise<void> {
  for (const [size, suffix] of [[DESKTOP, ''], [PHONE, '-phone']] as const) {
    await b.page.setViewport(size)
    await openCreate(b, `#/vms/create?machine=${HELPER_MACHINE}`)
    await b.page.waitForSelector(IMAGE, { timeout: SHORT_WAIT_MS })
    await b.until((trigger) => Number(document.querySelector(trigger)?.getAttribute('data-count')) === 3, { timeout: SHORT_WAIT_MS }, FRAMEWORK)
    await b.shot(`vms-create-default-agent${suffix}.png`)
    for (const [trigger, name] of [[IMAGE, 'server'], [FRAMEWORK, 'framework'], [RUNTIME, 'runtime']] as const) {
      await openedMenu(b, trigger)
      await b.shot(`vms-create-${name}-open${suffix}.png`)
      await b.page.keyboard.press('Escape')
    }
    await closeWithEscape(b)
  }
  await b.page.setViewport(DESKTOP)
}
