// The GPU in a real browser against a stand-in parent: the GPU choice on the Create form appears or not per machine and kind, the plain texts for a VM and for a missing toolkit,
// what the form sends, the small GPU badge, the note on a machine that lacks the toolkit, and "Check the GPU" with each answer (nvidia-smi, device files only, nothing),
// the errors, and hostile text from a machine staying text. The toolkit row of the Check list is in fix.e2e.ts (it needs the pretend Debian).
// Run: PANEL_DIST=<dir> SHOTS_DIR=<dir> bun e2e/gpu.e2e.ts   (needs a built panel, Google Chrome, `bun install` in frontend/)
import puppeteer from 'puppeteer-core'
import { CARD, CHECK_IDS, HOSTILE_DETAIL, REFUSED_CREATE, startGpuStandIn, type GpuStandIn } from './gpu/stand-in.ts'
import { check, finish } from './support/check.ts'
import { chromePath, panelDist } from './support/paths.ts'
import { GPU, RUNTIME, captionOf, choose, imageListArrived, lines, selectValue } from './support/createVm.ts'
import { wait } from './support/net.ts'
import { browse, type Browse } from './support/page.ts'

const SHORT_WAIT_MS = 10000
const SENT_TRIES = 50
const SENT_PAUSE_MS = 200
const SIZES = { desktop: { width: 1280, height: 1000 }, phone: { width: 400, height: 900 } }
const PICKER = '#vm-create-machine'
const GPU_LINES = [
  ['none', 'No GPU — CPU compute only', false],
  ['container', "GPU in a container — uses the machine's GPU", false],
  ['shared', 'Shared partition — coming soon', true],
  ['passthrough', 'Dedicated passthrough — coming soon (needs virtualization on the machine)', true],
  ['custom', 'Custom partition — coming soon', true],
]
const CONTAINER_CAPTION = "The container uses the machine's GPU together with the other containers on that machine. The share is a soft limit."
const NO_GPU_CAPTION = 'No GPU is given to this VM.'
const PLANNED_MODES = ['shared', 'passthrough', 'custom']
const VM_TEXT = "GPU in a VM is coming soon. It needs the machine's virtualization (SVM) switched on in its BIOS and the card passed through to one VM. Choose Container to use the GPU today."
const containerLineIsOff = (line: { options: { value: string; disabled: boolean }[] }) => line.options.find((option) => option.value === 'container')?.disabled === true
const TOOLKIT_TEXT = 'This machine needs the NVIDIA container toolkit first'

const openCreate = async (b: Browse, base: string, machine: string): Promise<void> => {
  await b.page.goto(`${base}/#/vms/create`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector(`dialog[open] ${PICKER}`, { timeout: SHORT_WAIT_MS })
  await b.page.select(PICKER, machine)
  await b.page.waitForSelector('#vm-create-name')
  await imageListArrived(b)
}

/** Waits until the stand-in parent has been asked to create this many VMs. */
async function untilSent(world: GpuStandIn, count: number): Promise<void> {
  for (let tries = 0; tries < SENT_TRIES && world.created.length < count; tries++) await wait(SENT_PAUSE_MS)
}

const pickKind = async (b: Browse, kind: string): Promise<void> => {
  await choose(b, RUNTIME, kind)
  await b.run(() => new Promise((done) => requestAnimationFrame(done)))
}

/** What the form says about the GPU right now: the select (if any) with its lines and caption, and the plain notes. */
const gpuLine = async (b: Browse) => ({
  options: await lines(b, GPU),
  picked: await selectValue(b, GPU),
  caption: (await b.page.$('dialog[open] #vm-create-gpu')) === null ? '' : await captionOf(b, GPU),
  notes: await b.run(() => [...document.querySelectorAll<HTMLElement>('[data-gpu-note]')].map((note) => ({ kind: note.dataset.gpuNote ?? '', text: note.innerText.trim() }))),
})

const nothingAboutGpu = async (b: Browse): Promise<boolean> => {
  const line = await gpuLine(b)
  return line.options.length === 0 && line.notes.length === 0
}

async function choiceByMachineAndKind(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, 'rtx-pc')
  let line = await gpuLine(b)
  check('a container-only PC with a card and the toolkit shows the GPU select: No GPU is picked, the real mode is on, the three planned ones are off', JSON.stringify(line.options.map((option) => [option.value, option.text, option.disabled])) === JSON.stringify(GPU_LINES) && line.picked === 'none', JSON.stringify(line))
  check('the line under the select says what No GPU means', line.caption === NO_GPU_CAPTION)
  await choose(b, GPU, 'container')
  check('picking the real mode changes it to what sharing means', (await gpuLine(b)).caption === CONTAINER_CAPTION)
  check('there is no VM text for a container', line.notes.length === 1 && line.notes[0]?.kind === 'choice')
  await b.shot('gpu-create-container.png')

  await openCreate(b, base, 'gpu-server')
  await pickKind(b, 'vm')
  line = await gpuLine(b)
  check('on a machine that runs VMs, the VM kind still shows the whole GPU select, No GPU picked, "GPU in a container" off, with the coming-soon caption', line.options.length === 5 && containerLineIsOff(line) && line.picked === 'none' && line.caption === VM_TEXT && line.notes[0]?.kind === 'vm_text', JSON.stringify(line))
  await b.shot('gpu-create-vm.png')
  await pickKind(b, 'container')
  line = await gpuLine(b)
  check('switching to Container turns "GPU in a container" on and shows what the choice means', line.options.length === 5 && !containerLineIsOff(line) && line.caption === NO_GPU_CAPTION && line.notes[0]?.kind === 'choice', JSON.stringify(line))
  await pickKind(b, 'vm')
  check('switching back to VM brings the coming-soon caption back', (await gpuLine(b)).caption === VM_TEXT)

  await openCreate(b, base, 'rtx-notoolkit')
  line = await gpuLine(b)
  const link = await b.run(() => document.querySelector<HTMLAnchorElement>('[data-gpu-note=toolkit] a')?.getAttribute('href') ?? '')
  check('a card without the toolkit keeps the select, with "GPU in a container" off, says the machine needs the toolkit first and links to the machine page', line.options.length === 5 && containerLineIsOff(line) && line.caption.startsWith(TOOLKIT_TEXT) && link === '#/machines/details?id=rtx-notoolkit', JSON.stringify({ line, link }))
  await b.shot('gpu-create-no-toolkit.png')

  for (const machine of ['mac-studio', 'plain-linux']) {
    await openCreate(b, base, machine)
    const vmKind = await nothingAboutGpu(b)
    await pickKind(b, 'container')
    check(`${machine}: no GPU line at all, for a VM or a container`, vmKind && (await nothingAboutGpu(b)))
  }
}

async function whatTheFormSends(b: Browse, world: GpuStandIn): Promise<void> {
  await openCreate(b, world.base, 'rtx-pc')
  await b.type('#vm-create-name', 'gpu-job')
  await choose(b, GPU, 'container')
  await b.click('Create VM')
  await b.until((text) => document.body.innerText.includes(text), { timeout: SHORT_WAIT_MS }, REFUSED_CREATE.slice(0, 40))
  const sent = world.created.at(-1)
  check('choosing Share sends gpu_mode container for a container on that machine', sent?.gpu_mode === 'container' && sent.kind === 'container' && sent.machine === 'rtx-pc' && sent.name === 'gpu-job', JSON.stringify(sent))
  check('the parent\'s plain refusal is shown as it is, and the choice is kept', (await b.text()).includes(REFUSED_CREATE) && (await gpuLine(b)).picked === 'container')
  await b.shot('gpu-create-refused.png')

  await choose(b, GPU, 'none')
  await b.click('Create VM')
  await untilSent(world, 2)
  await b.until(() => !document.querySelector('form[aria-label="Create VM"] [aria-busy=true]'), { timeout: SHORT_WAIT_MS })
  const plain = world.created.at(-1)
  check('No GPU sends no gpu_mode at all', world.created.length === 2 && plain !== undefined && !('gpu_mode' in plain), JSON.stringify(plain))

  for (const mode of PLANNED_MODES) {
    await openCreate(b, world.base, 'rtx-pc')
    await b.page.$eval(`dialog[open] ${GPU}`, (select, wanted) => { if (select instanceof HTMLSelectElement) { select.value = wanted; select.dispatchEvent(new Event('change', { bubbles: true })) } }, mode)
    await b.type('#vm-create-name', `planned-${mode}`)
    const before = world.created.length
    await b.click('Create VM')
    await untilSent(world, before + 1)
    const sentPlanned = world.created.at(-1)
    check(`even if "${mode}" reached the form it is never sent: no gpu_mode in the request`, sentPlanned?.name === `planned-${mode}` && !('gpu_mode' in sentPlanned), JSON.stringify(sentPlanned))
    await b.until(() => !document.querySelector('form[aria-label="Create VM"] [aria-busy=true]'), { timeout: SHORT_WAIT_MS })
  }

  await openCreate(b, world.base, 'gpu-server')
  await pickKind(b, 'container')
  await choose(b, GPU, 'container')
  await pickKind(b, 'vm')
  await b.type('#vm-create-name', 'vm-after')
  await b.click('Create VM')
  await b.until((count) => count > 0, { timeout: SHORT_WAIT_MS }, world.created.length - 2)
  const vm = world.created.at(-1)
  check('a VM never asks for the GPU, even after Share was chosen and the kind was changed', vm?.kind === 'vm' && !('gpu_mode' in vm), JSON.stringify(vm))
}

const badgesIn = (b: Browse, selector: string) => b.run((where) => [...document.querySelectorAll<HTMLElement>(where)].map((row) => ({ text: row.innerText.replace(/\s+/g, ' ').trim(), badge: row.querySelector('.gpu-badge') !== null })), selector)

async function badges(b: Browse, base: string): Promise<void> {
  await b.page.goto(`${base}/#/vms`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  const rows = await badgesIn(b, 'table[aria-label="VMs"] tbody tr')
  const withBadge = rows.filter((row) => row.badge).map((row) => row.text.split(' ')[0])
  check('in All VMs the containers that have the GPU carry a small GPU badge and the others do not', withBadge.length === 6 && !withBadge.includes('plain-box') && rows.find((row) => row.text.startsWith('plain-box'))?.badge === false, JSON.stringify(withBadge))
  await b.shot('gpu-badge-list.png')
  await b.page.goto(`${base}/#/machines/details?id=rtx-pc&vm=${CHECK_IDS.smi}`, { waitUntil: 'networkidle0' })
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, CHECK_IDS.smi)
  check('the container\'s own page shows the badge next to its name', await b.run(() => document.querySelector('.phead .gpu-badge') !== null))
  await b.page.goto(`${base}/#/machines/details?id=rtx-pc&vm=plain-box`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'plain-box', { timeout: SHORT_WAIT_MS })
  check('a container without the GPU has no badge and no GPU section', (await b.run(() => document.querySelector('.phead .gpu-badge') === null && document.querySelector('#gpu-heading') === null)))
}

async function machineNote(b: Browse, base: string): Promise<void> {
  const noteOn = async (id: string) => {
    await b.page.goto(`${base}/#/machines/details?id=${id}&tab=environment`, { waitUntil: 'networkidle0' })
    await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, id)
    return b.run(() => document.querySelector<HTMLElement>('[data-gpu-note=machine]')?.innerText ?? null)
  }
  const note = await noteOn('rtx-notoolkit')
  check('a machine with a card but no toolkit explains it on its page, with the fix', note !== null && /containers cannot use it yet/.test(note) && /apt-get install -y nvidia-container-toolkit/.test(note) && note.includes(CARD), note ?? 'none')
  await b.shot('gpu-machine-note.png')
  check('machines that are fine, a Mac and a plain Linux machine have no such note', (await noteOn('rtx-pc')) === null && (await noteOn('mac-studio')) === null && (await noteOn('plain-linux')) === null)
}

const resultText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-gpu-result]')?.innerText ?? '')

async function checkOne(b: Browse, base: string, id: string): Promise<string> {
  await b.page.goto(`${base}/#/machines/details?id=rtx-pc&vm=${id}`, { waitUntil: 'networkidle0' })
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, id)
  await b.click('Check the GPU')
  await b.until(() => (document.querySelector<HTMLElement>('[data-gpu-result]')?.innerText ?? '').trim() !== '', { timeout: SHORT_WAIT_MS })
  return resultText(b)
}

async function checkTheGpu(b: Browse, base: string): Promise<void> {
  const smi = await checkOne(b, base, CHECK_IDS.smi)
  check('nvidia-smi answered: the GPU is visible, with the card and driver as evidence', smi.includes('The GPU is visible inside.') && smi.includes(`Seen with nvidia-smi: ${CARD}, 580.178.04, 32607 MiB`), smi)
  await b.shot('gpu-check-smi.png')
  const devices = await checkOne(b, base, CHECK_IDS.devices)
  check('only the device files: visible, and the note says nvidia-smi is not installed in this image', devices.includes('The GPU is visible inside.') && devices.includes('nvidia-smi is not installed in this image') && devices.includes('/dev/nvidia0'), devices)
  await b.shot('gpu-check-devices.png')
  const nothing = await checkOne(b, base, CHECK_IDS.nothing)
  check('nothing found: not visible, with its note and the evidence line', nothing.includes('The GPU is not visible inside.') && nothing.includes('no nvidia-smi and no NVIDIA device file') && nothing.includes('Nothing found'), nothing)
  await b.shot('gpu-check-nothing.png')
  const hostile = await checkOne(b, base, CHECK_IDS.hostile)
  const injected = await b.run(() => ({ flag: window.__gpuxss, images: document.querySelectorAll('[data-gpu-result] img, [data-gpu-result] script, [data-gpu-result] b').length }))
  check('hostile text from the machine stays text: shown as written, nothing runs, no tag appears', hostile.includes(HOSTILE_DETAIL) && hostile.includes('<b>bold</b> note') && injected.flag === undefined && injected.images === 0, JSON.stringify(injected))
  await b.shot('gpu-check-hostile.png')
  const down = await checkOne(b, base, CHECK_IDS.down)
  check('a machine that does not answer is said plainly', down.includes('the machine did not answer'), down)
  const stopped = await checkOne(b, base, CHECK_IDS.stopped)
  check('a stopped container is told to start first', stopped.includes('start it first'), stopped)
}

async function onAPhone(b: Browse, base: string): Promise<void> {
  await b.page.setViewport(SIZES.phone)
  const noSideScroll = () => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)
  await openCreate(b, base, 'rtx-pc')
  check('Create VM with the GPU choice has no sideways scrolling on a phone', await noSideScroll())
  await b.shot('gpu-create-container-phone.png', true)
  await openCreate(b, base, 'rtx-notoolkit')
  await b.shot('gpu-create-no-toolkit-phone.png', true)
  await checkOne(b, base, CHECK_IDS.devices)
  check('the Check the GPU answer has no sideways scrolling on a phone', await noSideScroll())
  await b.shot('gpu-check-phone.png', true)
  await b.page.setViewport(SIZES.desktop)
}

const world = startGpuStandIn(panelDist)
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
try {
  const page = await browser.newPage()
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  page.on('console', (message) => message.type() === 'error' && !/status of (409|502)/.test(message.text()) && errors.push(message.text()))
  await page.evaluateOnNewDocument(() => document.addEventListener('securitypolicyviolation', (event) => { window.violation = event.violatedDirective }))
  const b = browse(page)
  await choiceByMachineAndKind(b, world.base)
  await whatTheFormSends(b, world)
  await badges(b, world.base)
  await machineNote(b, world.base)
  await checkTheGpu(b, world.base)
  await onAPhone(b, world.base)
  check('no script errors and no policy violations', errors.length === 0 && (await b.run(() => window.violation)) === undefined, errors.join(' | '))
} finally {
  await browser.close()
  world.stop()
}
finish()
