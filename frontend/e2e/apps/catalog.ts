// The Install on top menu with OpenClaw and Hermes, and creating a VM that carries one of them, in a real browser against the stand-in Root.
// Selectable only when the catalog says so (and the catalog's own reason otherwise), the bundled MAAS logos draw in full colour when selectable and grey when not, no logo comes from another site,
// the request carries `bundle` once for five rapid clicks, and the plain Ubuntu request is exactly what it always was.
import type { Page } from 'puppeteer-core'
import { APP_CAPTION, OLD_HELPER_REASON } from '../actions/appBook.ts'
import { burst, fresh } from '../actions/guard.ts'
import type { StandIn } from '../actions/standin.ts'
import { check } from '../support/check.ts'
import { FRAMEWORK, NAME, choose, openedMenu } from '../support/createVm.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'

export const MACHINE_VMS = '#/machines/details?id=studio&tab=vms'
export const SHORT_WAIT_MS = 10_000
export const PHONE = { width: 400, height: 844 }
export const DESKTOP = { width: 1280, height: 800 }
const RAPID_CLICKS = 5
const SLOW_MS = 700
const SETTLE_MS = 1600
const FRAMEWORK_ROWS_WITH_CATALOG = 7
const PLAIN_BODY = '{"name":"plain-box","kind":"vm","cpu":2,"ram_mb":4096,"disk_gb":40,"machine":"studio"}'

interface LogoView {
  src: string
  drawn: boolean
  muted: boolean
  filter: string
}

/** Opens the Create VM window from the machine page and waits for the machine's image list. */
export async function openCreateWindow(b: Browse): Promise<void> {
  await b.click('＋ New VM')
  await b.page.waitForSelector(FRAMEWORK, { timeout: SHORT_WAIT_MS })
  await b.until((trigger, wanted) => Number(document.querySelector(trigger)?.getAttribute('data-count')) === wanted, { timeout: SHORT_WAIT_MS }, FRAMEWORK, FRAMEWORK_ROWS_WITH_CATALOG)
}

/** Starts the stand-in over, lets the test set it up, and only then opens the page, so the first answers already say what the test wants. */
export async function openConfigured(b: Browse, standin: StandIn, hash: string, setup: () => void): Promise<void> {
  standin.reset()
  setup()
  await b.page.goto('about:blank')
  await b.page.goto(`${standin.base}/${hash}`, { waitUntil: 'networkidle0' })
}

const logoOf = async (b: Browse, value: string): Promise<LogoView | null> => {
  await b.until((wanted) => {
    const img = document.querySelector(`dialog[open] [role=option][data-value="${wanted}"] .badge img`)
    return img instanceof HTMLImageElement && img.complete
  }, { timeout: SHORT_WAIT_MS }, value)
  return b.run((wanted) => {
    const row = document.querySelector(`dialog[open] [role=option][data-value="${wanted}"]`)
    const img = row?.querySelector('.badge img')
    if (!row || !img || !(img instanceof HTMLImageElement)) return null
    return { src: img.currentSrc, drawn: img.complete && img.naturalWidth > 0, muted: row.querySelector('.badge')?.classList.contains('muted') === true, filter: getComputedStyle(img).filter }
  }, value)
}

/** Collects the address of every request that is not for the stand-in itself or a data picture. */
export function watchOutsideRequests(page: Page, base: string): string[] {
  const outside: string[] = []
  page.on('request', (request) => {
    const address = request.url()
    if (!address.startsWith(base) && !address.startsWith('data:') && !address.startsWith('about:') && !address.startsWith('blob:')) outside.push(address)
  })
  return outside
}

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth && [...document.querySelectorAll<HTMLElement>('dialog[open]')].every((dialog) => dialog.scrollWidth <= dialog.clientWidth))

/** The catalog says both are ready: both can be picked, with its caption, the Installs on start chip and their own logo in full colour. */
export async function selectableWhenReady(b: Browse, standin: StandIn): Promise<void> {
  const outside = watchOutsideRequests(b.page, standin.base)
  await fresh(b, standin, MACHINE_VMS)
  await openCreateWindow(b)
  const list = await openedMenu(b, FRAMEWORK)
  const [none, openclaw, hermes] = list.rows
  check('Install on top lists None, OpenClaw, Hermes, then the four planned', list.rows.map((row) => row.title).join('|') === 'None — just the server|OpenClaw|Hermes|Docker|Ollama|Python + Jupyter|Node.js', JSON.stringify(list.rows.map((row) => row.title)))
  check('None is picked and OpenClaw and Hermes are not greyed out', none?.selected === true && openclaw?.disabled === false && hermes?.disabled === false, JSON.stringify(list.rows.slice(0, 3)))
  check('they show the catalog caption and an Installs on start chip, never Coming soon', [openclaw, hermes].every((row) => row?.caption === APP_CAPTION && row.tag === 'Installs on start'), JSON.stringify([openclaw, hermes]))
  check('the four planned ones stay greyed out with Coming soon', list.rows.slice(3).every((row) => row.disabled && row.tag === 'Coming soon'))
  const logos = [await logoOf(b, 'openclaw'), await logoOf(b, 'hermes')]
  check('OpenClaw has its bundled svg and Hermes its bundled webp, both drawn, in full colour', logos[0]?.src.endsWith('.svg') === true && logos[1]?.src.endsWith('.webp') === true && logos.every((logo) => logo?.drawn === true && !logo.muted && logo.filter === 'none'), JSON.stringify(logos))
  const planned = await logoOf(b, 'preview-docker')
  check('a planned row keeps its logo greyed out', planned?.muted === true && planned.filter.includes('grayscale'), JSON.stringify(planned))
  check('every logo comes from the panel itself (no request to another site)', outside.length === 0, outside.join(' | '))
  await b.shot('apps-install-on-top-desktop.png')
  await b.page.setViewport(PHONE)
  await wait(SETTLE_MS / 4)
  check('phone 400px: the open menu does not scroll sideways', await noSideScroll(b))
  await b.shot('apps-install-on-top-phone.png')
  await b.page.setViewport(DESKTOP)
}

/** An old helper: both are greyed out with the catalog's reason, and neither can be picked. */
export async function greyedForAnOldHelper(b: Browse, standin: StandIn): Promise<void> {
  standin.apps.catalog = 'old_helper'
  await b.page.goto('about:blank')
  await b.page.goto(`${standin.base}/${MACHINE_VMS}`, { waitUntil: 'networkidle0' })
  await openCreateWindow(b)
  const list = await openedMenu(b, FRAMEWORK)
  const [, openclaw, hermes] = list.rows
  check('with an old helper OpenClaw and Hermes are greyed out and say what to do', [openclaw, hermes].every((row) => row?.disabled === true && row.caption === OLD_HELPER_REASON && row.tag !== 'Installs on start'), JSON.stringify([openclaw, hermes]))
  const logo = await logoOf(b, 'openclaw')
  check('and their logos are greyed out', logo?.muted === true && logo.filter.includes('grayscale'), JSON.stringify(logo))
  await b.click('Cancel')
}

/** The bundle a create request body carries, or undefined when it carries none. */
function bundleOf(body: string): unknown {
  const parsed: unknown = JSON.parse(body)
  return typeof parsed === 'object' && parsed !== null && 'bundle' in parsed ? parsed.bundle : undefined
}

/** Picks the framework, names the VM and presses Create VM five times as fast as the browser can. */
async function createWith(b: Browse, standin: StandIn, bodies: string[], framework: string, name: string): Promise<void> {
  await fresh(b, standin, MACHINE_VMS)
  bodies.length = 0
  await openCreateWindow(b)
  await b.type(NAME, name)
  if (framework !== 'none') await choose(b, FRAMEWORK, framework)
  standin.apps.delayMs = SLOW_MS
  await burst(b, 'Create VM', RAPID_CLICKS)
  await wait(SETTLE_MS)
}

/** Creating with OpenClaw or Hermes sends the bundle, once for five rapid clicks; plain Ubuntu sends what it always sent. `bodies` holds the raw body of every create request the page sends. */
export async function createSendsTheBundle(b: Browse, standin: StandIn, bodies: string[]): Promise<void> {
  for (const app of ['openclaw', 'hermes']) {
    await createWith(b, standin, bodies, app, `${app}-box`)
    check(`${app}: five rapid clicks send one create request to the Root`, bodies.length === 1 && standin.createBodies.length === 1, `${bodies.length} from the page, ${standin.createBodies.length} at the Root`)
    check(`${app}: it carries bundle "${app}"`, bodies.length === 1 && bundleOf(bodies[0] ?? '') === app, bodies.join(' | '))
  }
  await createWith(b, standin, bodies, 'none', 'plain-box')
  check('plain Ubuntu: the request is byte for byte what it was before apps (no bundle, no image)', bodies.length === 1 && bodies[0] === PLAIN_BODY, bodies.join(' | '))
}
