// A VM that is being made shows as a "Creating…" card behind the Create VM window (All VMs, or the machine's page) and on the other pages until its machine lists it, and a failed order stays with its reason until dismissed.
// The parent's answers about the orders are played by the test (so each stage can be looked at as long as needed); the machine and its heartbeats are real.
import type { HTTPRequest, Page } from 'puppeteer-core'
import { check } from '../support/check.ts'
import { NAME, closeProgress, imageListArrived } from '../support/createVm.ts'
import { noSideScroll, owlAbsent, owlShown } from '../support/owls.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from '../panel/machines.ts'
import { enrollMachine, resendHeartbeats, sendHeartbeat, type World } from '../panel/world.ts'
import { openCreate } from './create.ts'

const MACHINE = 'pend-mac'
const GOOD_VM = 'pending-box'
const BAD_VM = 'bad-box'
const NEW_ID = 'wl-pending'
const SHORT_WAIT_MS = 10000
const LIST_WAIT_MS = 25000
const PENDING_MAX_PX = 60
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }

interface Order {
  id: string
  type: 'create'
  machine: string
  state: 'queued' | 'running' | 'succeeded' | 'failed'
  created_at: string
  finished_at?: string
  params: { name: string }
  result?: { error?: string; workload_id?: string }
}

/** The order the test plays for the parent; null lets every request through untouched. */
interface Stand { order: Order | null }

const json = (request: HTTPRequest, status: number, body: unknown) => request.respond({ status, contentType: 'application/json', body: JSON.stringify(body) })

async function answer(request: HTTPRequest, stand: Stand): Promise<void> {
  const order = stand.order
  const where = new URL(request.url()).pathname
  const get = request.method() === 'GET'
  if (order && request.method() === 'POST' && where === '/api/workloads') return json(request, 202, { command: order })
  if (order && get && where === '/api/commands') return json(request, 200, { commands: [order] })
  if (order && get && where === `/api/commands/${order.id}`) return json(request, 200, { command: order })
  return request.continue()
}

const newOrder = (id: string, name: string, state: Order['state'], extra: Partial<Order> = {}): Order => ({ id, type: 'create', machine: MACHINE, state, created_at: new Date().toISOString(), params: { name }, ...extra })
const card = (name: string) => `ul.pending li[data-pending="${name}"]`
const cardText = (b: Browse, name: string) => b.run((selector) => document.querySelector<HTMLElement>(selector)?.innerText ?? '', card(name))
const hasCard = (b: Browse, name: string) => b.run((selector) => document.querySelector(selector) !== null, card(name))
/** Waits for the card's own stage label (the tag), which says "Creating…" and the like; the three step names are always there. */
const untilCardSays = (b: Browse, name: string, words: string, timeout = SHORT_WAIT_MS) => b.until((selector, wanted) => (document.querySelector<HTMLElement>(`${selector} .tag`)?.textContent ?? '') === wanted, { timeout }, card(name), words)

async function submitCreate(b: Browse, name: string): Promise<void> {
  await openCreate(b, `#/vms/create?machine=${MACHINE}`)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
  await b.type(NAME, name)
  await b.click('Create VM')
}

async function creatingFromTheWindow(b: Browse, stand: Stand): Promise<void> {
  stand.order = newOrder('rc-e2e-1', GOOD_VM, 'queued')
  await submitCreate(b, GOOD_VM)
  await closeProgress(b)
  await untilCardSays(b, GOOD_VM, 'Waiting for the machine…')
  const text = await cardText(b, GOOD_VM)
  check('right after Create the window closes, All VMs is behind it, and a card names the VM and its machine and says it is waiting for the machine', text.includes(GOOD_VM) && text.includes(MACHINE) && /waiting for the machine…/i.test(text) && b.page.url().endsWith('#/vms'), text)
  check('the card shows three steps with the current one marked', (await b.run(() => document.querySelectorAll('ul.pending li[data-pending] ol.steps li').length)) === 3 && (await b.run(() => document.querySelectorAll('ul.pending li[aria-current="step"], ul.pending li [aria-current="step"]').length)) === 1)
  await owlShown(b, 'busy', 'the Creating card')
  await owlAbsent(b, 'emptyVms', 'All VMs while the first VM is being made')
  await b.shot('pending-create-waiting.png')
  stand.order = newOrder('rc-e2e-1', GOOD_VM, 'running')
  await untilCardSays(b, GOOD_VM, 'Creating…')
  check('when the machine takes the order the current step moves to creating', (await b.run(() => document.querySelector('ul.pending li [aria-current="step"]')?.textContent?.trim() ?? '')) === 'Creating')
  await b.page.setViewport(PHONE)
  await noSideScroll(b, 'the Creating card on a phone')
  await b.shot('pending-create-phone.png', true)
  await b.page.setViewport(DESKTOP)
}

async function onTheOtherPages(b: Browse, stand: Stand): Promise<void> {
  await b.go('#/vms')
  await b.until((selector) => document.querySelector(selector) !== null, { timeout: LIST_WAIT_MS }, card(GOOD_VM))
  check('All VMs shows the pending VM above its table', (await cardText(b, GOOD_VM)).includes(MACHINE))
  await b.shot('pending-all-vms.png')
  await b.page.setViewport(PHONE)
  await b.shot('pending-all-vms-phone.png', true)
  await b.page.setViewport(DESKTOP)
  await b.go(`#/machines/details?id=${MACHINE}`)
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, MACHINE)
  check('the machine page shows the pending VM and counts it in VMs', (await hasCard(b, GOOD_VM)) && /VMs\s*\(1\)/.test(await b.text()))
  check('on the machine page the Creating card adds at most 60 px above the tabs', await b.run((limit) => (document.querySelector<HTMLElement>('ul.pending')?.getBoundingClientRect().height ?? Infinity) <= limit, PENDING_MAX_PX))
  await openTab(b, 'Activity')
  check('the Creating card is still there on another tab', await hasCard(b, GOOD_VM))
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  const text = await b.text()
  await owlAbsent(b, 'emptyVms', 'the machine page while a VM is being made')
  check('while a VM is being made the machine page never says there are no VMs', !/No VMs on this machine yet\./.test(text) && /is being made/.test(text), text.slice(0, 300))
  await b.shot('pending-machine-page.png')
  await b.page.setViewport(PHONE)
  await b.shot('pending-machine-page-phone.png', true)
  await b.page.setViewport(DESKTOP)
  stand.order = newOrder('rc-e2e-1', GOOD_VM, 'succeeded', { finished_at: new Date().toISOString(), result: { workload_id: NEW_ID } })
  await untilCardSays(b, GOOD_VM, 'Starting…', LIST_WAIT_MS)
  check('a made VM that the machine has not listed yet is shown as starting', (await b.run((selector) => document.querySelector(`${selector} .tag`)?.textContent?.trim() ?? '', card(GOOD_VM))) === 'Starting…')
  await b.shot('pending-machine-starting.png')
}

async function listedByTheMachine(b: Browse, world: World, token: string): Promise<void> {
  await sendHeartbeat(world, token, heartbeat([{ id: NEW_ID, name: GOOD_VM, kind: 'vm', state: 'running', cpu: 1, ram_mb: 1024, disk_gb: 10, gpu_mode: 'none', address: null, bundle_version: null }]))
  await b.until((selector) => document.querySelector(selector) === null && document.body.innerText.includes('VMs (1)'), { timeout: LIST_WAIT_MS }, card(GOOD_VM))
  check('once the machine lists the VM the pending card is replaced by the real VM', !(await hasCard(b, GOOD_VM)) && /VMs\s*\(1\)/.test(await b.text()))
  await b.shot('pending-machine-listed.png')
}

async function aFailedOrder(b: Browse, stand: Stand): Promise<void> {
  stand.order = newOrder('rc-e2e-2', BAD_VM, 'failed', { finished_at: new Date().toISOString(), result: { error: 'the machine could not create the workload' } })
  await submitCreate(b, BAD_VM)
  await closeProgress(b)
  await untilCardSays(b, BAD_VM, 'Could not make the VM')
  const text = await cardText(b, BAD_VM)
  check('a failed order keeps its card with the helper\'s reason in a sentence and a Dismiss button', /The machine could not create the workload\./.test(text) && /Dismiss/.test(text), text)
  check('the window is closed and the failed order sits on the page behind it', (await b.run(() => document.querySelector('dialog[open]') === null)) && (await hasCard(b, BAD_VM)))
  check('a failed order card shows no busy owl', await b.run((selector) => document.querySelector(`${selector} img[data-owl]`) === null, card(BAD_VM)))
  await b.shot('pending-failed.png')
  await b.page.setViewport(PHONE)
  await b.shot('pending-failed-phone.png', true)
  await b.page.setViewport(DESKTOP)
  await b.go('#/vms')
  await b.until((selector) => document.querySelector(selector) !== null, { timeout: SHORT_WAIT_MS }, card(BAD_VM))
  check('the failed order stays on other pages too', await hasCard(b, BAD_VM))
  await b.run((selector) => document.querySelector<HTMLButtonElement>(`${selector} button`)?.click(), card(BAD_VM))
  await b.until((selector) => document.querySelector(selector) === null, { timeout: SHORT_WAIT_MS }, card(BAD_VM))
  check('Dismiss removes the failed card', !(await hasCard(b, BAD_VM)))
}

const heartbeat = (workloads: unknown[]) => ({
  facts: { os: 'macos', arch: 'arm64', cpu_cores: 8, ram_total_mb: 16384, disk_total_gb: 500, free_ram_mb: 8000, free_disk_gb: 300, gpu: [], capabilities: { vm: true, container: false, gpu_in_vm: false, gpu_in_container: false }, problems: [] },
  workloads,
  bundle_version: null,
})

export async function pendingScenario(b: Browse, world: World): Promise<void> {
  if (!world.session) throw new Error('seed the world first')
  const token = await enrollMachine(world, world.session, MACHINE)
  await sendHeartbeat(world, token, heartbeat([]))
  await resendHeartbeats(world)
  const stand: Stand = { order: null }
  const page: Page = b.page
  const handler = (request: HTTPRequest) => void answer(request, stand)
  await page.setRequestInterception(true)
  page.on('request', handler)
  await b.page.reload({ waitUntil: 'networkidle0' })
  await creatingFromTheWindow(b, stand)
  await resendHeartbeats(world)
  await onTheOtherPages(b, stand)
  await resendHeartbeats(world)
  await listedByTheMachine(b, world, token)
  await aFailedOrder(b, stand)
  stand.order = null
  page.off('request', handler)
  await page.setRequestInterception(false)
}
