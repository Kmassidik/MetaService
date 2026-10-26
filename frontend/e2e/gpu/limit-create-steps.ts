// The Create VM window with a GPU memory limit, in a real browser: the options and their reasons per machine, the number field, its live checks, what is sent, a server refusal, and a reset when the machine changes.
import { check } from '../support/check.ts'
import { GPU, captionOf, choose, imageListArrived, lines, selectValue } from '../support/createVm.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { BLIND_PC, FULL_PC, OLD_PC, PLAIN_PC, SHARE_PC, TOTAL_GB, type LimitStandIn } from './limit-stand-in.ts'

const SHORT_WAIT_MS = 10000
const SENT_TRIES = 50
const SENT_PAUSE_MS = 200
const RAPID_CLICKS = 5
const PICKER = '#vm-create-machine'
const MEMORY = '#vm-create-gpu-memory'
const SHARED_LABEL = "Shared partition — limit this VM's GPU memory"
const OPTION_ORDER = ['none', 'container', 'shared', 'passthrough']
const FREE_GB = TOTAL_GB - 8
const DEFAULT_GB = 4
const OVER_TEXT = `Only ${FREE_GB} GB of the card is free, so ${FREE_GB + 1} GB cannot be reserved.`
const HINT_TEXT = 'The limit stays booked for this VM even while it is stopped.'
const WARNING_TEXT = 'If the VM stays over its limit for about 15 seconds it is stopped.'
const REFUSAL_TEXT = "Only 20 GB of the card's 31 GB is still free to book."
const FREE_LINE_START = `GPU: ${FREE_GB} GB free of `
const REASONS: [string, string][] = [
  [OLD_PC, 'Update the helper on this machine first.'],
  [FULL_PC, 'The card is fully in use.'],
  [BLIND_PC, 'This machine cannot book GPU memory.'],
]

/** A fresh Create VM window: going to the same address again would keep an open window and its choices, so leave for the list first. */
export async function openCreate(b: Browse, base: string, machine: string): Promise<void> {
  await b.page.goto(`${base}/#/vms`, { waitUntil: 'networkidle0' })
  await b.page.goto(`${base}/#/vms/create`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector(`dialog[open] ${PICKER}`, { timeout: SHORT_WAIT_MS })
  await b.page.select(PICKER, machine)
  await b.page.waitForSelector('#vm-create-name')
  await imageListArrived(b)
}

async function untilSent(world: LimitStandIn, count: number): Promise<void> {
  for (let tries = 0; tries < SENT_TRIES && world.created.length < count; tries++) await wait(SENT_PAUSE_MS)
}

const memoryState = (b: Browse) =>
  b.run((selector) => {
    const input = document.querySelector<HTMLInputElement>(`dialog[open] ${selector}`)
    const problem = document.querySelector<HTMLElement>('dialog[open] [data-gpu-memory-problem]')
    const box = document.querySelector<HTMLElement>('dialog[open] [data-gpu-memory]')
    return { value: input?.value ?? null, min: input?.min ?? null, max: input?.max ?? null, problem: problem?.innerText.trim() ?? null, text: box?.innerText ?? '', label: box?.querySelector('label')?.textContent?.trim() ?? null }
  }, MEMORY)

const createDisabled = (b: Browse) => b.isDisabled('Create VM')

/** After a good Create the form goes; the progress window may follow (it only stays while the order is working), so close whatever is left open. */
async function waitForClosed(b: Browse): Promise<void> {
  await b.until(() => document.querySelector('dialog[open] form[aria-label="Create VM"]') === null, { timeout: SHORT_WAIT_MS })
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
}

export async function optionsPerMachine(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, SHARE_PC)
  const shared = (await lines(b, GPU)).find((line) => line.value === 'shared')
  const order = (await lines(b, GPU)).map((line) => line.value)
  check('on a machine with 23 GB free the options are None, Container, Shared partition, Dedicated passthrough, and Custom partition is gone', JSON.stringify(order) === JSON.stringify(OPTION_ORDER), order.join(','))
  check('Shared partition is enabled there, with its exact label', shared?.disabled === false && shared.text === SHARED_LABEL, JSON.stringify(shared))
  const free = await b.run(() => document.querySelector('dialog[open] [data-gpu-room]')?.textContent?.trim() ?? '')
  check(`the card's free memory sits next to the choice: "${FREE_LINE_START}…"`, free.startsWith(FREE_LINE_START), free)
  for (const [machine, reason] of REASONS) {
    await openCreate(b, base, machine)
    const line = (await lines(b, GPU)).find((entry) => entry.value === 'shared')
    check(`${machine}: Shared partition is off and says why: ${reason}`, line?.disabled === true && line.text === `${SHARED_LABEL} (${reason})`, JSON.stringify(line))
  }
  await openCreate(b, base, PLAIN_PC)
  check('a machine without a GPU has no GPU select', (await lines(b, GPU)).length === 0)
}

export async function numberField(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, SHARE_PC)
  check('no number field while No GPU is picked', (await memoryState(b)).value === null)
  await choose(b, GPU, 'shared')
  await b.page.waitForSelector(MEMORY)
  const field = await memoryState(b)
  check('choosing Shared partition shows "GPU memory for this VM (GB)" with the default 4, min 1 and max the free GB', field.label === 'GPU memory for this VM (GB)' && field.value === String(DEFAULT_GB) && field.min === '1' && field.max === String(FREE_GB), JSON.stringify(field))
  check('the hint and the grey warning line are shown', field.text.includes(HINT_TEXT) && field.text.includes(WARNING_TEXT), field.text)
  check('a shared partition has a plain caption and Create is ready', (await captionOf(b, GPU)).includes('only the GPU memory you set') && !(await createDisabled(b)))
  await b.shot('gpu-limit-select-shared.png')
  await b.type(MEMORY, String(FREE_GB + 1))
  const over = await memoryState(b)
  check('a value over the free GB shows a plain message and blocks Create', over.problem === OVER_TEXT && (await createDisabled(b)), JSON.stringify(over))
  await b.type(MEMORY, '0')
  check('0 is refused with a plain message', (await memoryState(b)).problem?.startsWith('GPU memory must be a whole number') === true && (await createDisabled(b)))
  await b.page.$eval(`dialog[open] ${MEMORY}`, (input) => { if (input instanceof HTMLInputElement) { input.value = ''; input.dispatchEvent(new Event('input', { bubbles: true })) } })
  check('an empty number blocks Create', (await createDisabled(b)))
  await b.type(MEMORY, String(FREE_GB))
  check('the largest free value is accepted', (await memoryState(b)).problem === null && !(await createDisabled(b)))
}

export async function machineChangeResets(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, SHARE_PC)
  await choose(b, GPU, 'shared')
  await b.type(MEMORY, '12')
  await b.page.select(PICKER, BLIND_PC)
  await b.until(() => document.querySelector('dialog[open] #vm-create-gpu-memory') === null, { timeout: SHORT_WAIT_MS })
  check('moving to a machine that cannot book returns the choice to No GPU and the number goes away', (await selectValue(b, GPU)) === 'none')
  await b.page.select(PICKER, SHARE_PC)
  await choose(b, GPU, 'shared')
  await b.page.waitForSelector(MEMORY)
  check('coming back, Shared partition starts again at the default, not at the old 12', (await memoryState(b)).value === String(DEFAULT_GB), JSON.stringify(await memoryState(b)))
}

export async function sendsTheOldBodies(b: Browse, world: LimitStandIn): Promise<void> {
  await openCreate(b, world.base, SHARE_PC)
  await b.type('#vm-create-name', 'no-gpu-job')
  await b.click('Create VM')
  await untilSent(world, 1)
  await waitForClosed(b)
  const plain = world.created.at(-1)
  check('No GPU sends neither gpu_mode nor gpu_memory_gb', plain?.name === 'no-gpu-job' && !('gpu_mode' in plain) && !('gpu_memory_gb' in plain), JSON.stringify(plain))
  await openCreate(b, world.base, SHARE_PC)
  await b.type('#vm-create-name', 'whole-job')
  await choose(b, GPU, 'container')
  await b.click('Create VM')
  await untilSent(world, 2)
  await waitForClosed(b)
  const whole = world.created.at(-1)
  check('the whole card sends gpu_mode container and no gpu_memory_gb, as before', whole?.name === 'whole-job' && whole.gpu_mode === 'container' && !('gpu_memory_gb' in whole), JSON.stringify(whole))
}

export async function serverRefusalStaysInTheModal(b: Browse, world: LimitStandIn): Promise<void> {
  await openCreate(b, world.base, SHARE_PC)
  await b.type('#vm-create-name', 'refused-job')
  await choose(b, GPU, 'shared')
  world.refuseNext(409, { code: 'gpu_memory_not_available', message: REFUSAL_TEXT, free_gb: 20 })
  const before = world.created.length
  await b.click('Create VM')
  await b.until((text) => (document.querySelector('dialog[open]')?.textContent ?? '').includes(text), { timeout: SHORT_WAIT_MS }, REFUSAL_TEXT)
  check('a 409 gpu_memory_not_available shows its message inside the modal and the modal stays open with the choice kept', world.created.length === before + 1 && (await selectValue(b, GPU)) === 'shared' && (await memoryState(b)).value === String(DEFAULT_GB))
  await b.shot('gpu-limit-refused.png')
}

/** Five quick clicks on Create send one request, with the limit; then the booking shows on the machine. */
export async function oneRequestForRapidClicks(b: Browse, world: LimitStandIn): Promise<void> {
  await openCreate(b, world.base, SHARE_PC)
  await b.type('#vm-create-name', 'limit-job')
  await choose(b, GPU, 'shared')
  await b.type(MEMORY, '6')
  const before = world.created.length
  await b.run((count) => {
    const button = [...document.querySelectorAll('dialog[open] button')].find((entry) => entry.textContent?.trim() === 'Create VM')
    for (let click = 0; click < count; click++) button?.dispatchEvent(new MouseEvent('click', { bubbles: true }))
  }, RAPID_CLICKS)
  await untilSent(world, before + 1)
  await waitForClosed(b)
  await wait(SENT_PAUSE_MS * 2)
  const sent = world.created.slice(before)
  check('five rapid Create clicks send ONE request with gpu_mode container and gpu_memory_gb 6', sent.length === 1 && sent[0]?.gpu_mode === 'container' && sent[0].gpu_memory_gb === 6 && sent[0].kind === 'container' && sent[0].name === 'limit-job', JSON.stringify(sent))
}
