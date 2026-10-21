// Why a VM stopped, as the machine reported it: on the VM's own page, in the VM lists, and in the terminal window (which explains instead of showing an error,
// and has a Start button that works). The log lines come from inside the VM, so a hostile one must stay text.
import { writeHeaders } from '../support/admin.ts'
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from './machines.ts'
import { createAVm } from './workloads.ts'
import { untilConnected } from './terminal.ts'
import { enrollMachine, resendHeartbeats, sendHeartbeat, startAgent, type World } from './world.ts'

const MACHINE = 'stop-mac'
const AGENT_MACHINE = 'agent-mac'
const SHORT_WAIT_MS = 10000
const AGENT_WAIT_MS = 20000
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }
const SETTLE_MS = 1500
const ID_ATTEMPTS = 30
const ID_PAUSE_MS = 1000
/** Longer than the five seconds after which a shell that ends is called "right after it started". */
const LONG_ENOUGH_MS = 6500
const REASON_LOG = 'Failed to mount tmpfs (type tmpfs) on /run: Operation not permitted\n[!!!!!!] Failed to mount API filesystems.\nExiting PID 1...'
const HOSTILE_IMG = '<img src=x onerror="window.__xss=1">'
const HOSTILE_LOG = `${HOSTILE_IMG}\n<script>window.__xss=2</script>\n\u001b[31mcolour\u001b[0m`
const QUIET_TEXT = 'It stopped on its own; the machine did not say why yet.'
const PLAIN_TEXT = 'This VM runs without systemd'
const BROKEN_ERROR = /error · the VM is not running/i

const vm = (id: string, name: string, state: string, extra: Record<string, unknown> = {}) =>
  ({ id, name, kind: 'vm', state, cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: null, bundle_version: null, ...extra })

const facts = { os: 'macos', arch: 'arm64', cpu_cores: 8, ram_total_mb: 16384, disk_total_gb: 500, free_ram_mb: 8000, free_disk_gb: 300, gpu: [], capabilities: { vm: true, container: false, gpu_in_vm: false, gpu_in_container: false }, problems: [] }

const dead = vm('w-dead', 'test', 'stopped', { stopped_reason: { exit_code: 255, log_tail: REASON_LOG } })
const evil = vm('w-evil', 'evil', 'stopped', { stopped_reason: { exit_code: null, log_tail: HOSTILE_LOG } })
const quiet = vm('w-quiet', 'quiet', 'stopped')
const plain = vm('w-plain', 'plain', 'running', { init_mode: 'plain' })
const stale = vm('w-stale', 'stale', 'running')

const beat = (workloads: unknown[]) => ({ facts, workloads, bundle_version: null })

async function vmPage(b: Browse, id: string, name: string): Promise<void> {
  await b.go(`#/machines/details?id=${MACHINE}&vm=${id}`)
  await b.until((wanted) => document.querySelector('.phead h1')?.textContent === wanted, { timeout: SHORT_WAIT_MS }, name)
}

const whyText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('.tabbody .why')?.innerText ?? '')
const noSidewaysScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

async function theVmPage(b: Browse): Promise<void> {
  await vmPage(b, 'w-dead', 'test')
  const why = await whyText(b)
  check('the page of a VM that stopped by itself has a "Why it stopped" block with the exit code', /Why it stopped/i.test(why) && why.includes('Exit code 255.'), why)
  check('the block shows the last lines the VM printed, as text', why.includes('Failed to mount API filesystems.') && why.includes('Exiting PID 1...'), why)
  check('the block has a Copy button', await b.run(() => [...document.querySelectorAll('.tabbody .why button')].some((button) => button.textContent?.trim() === 'Copy')))
  check('the block is the usual small code box: plain text, no markup', await b.run(() => document.querySelectorAll('.tabbody .why code').length === 1 && document.querySelectorAll('.tabbody .why *:not(code):not(p):not(div):not(button)').length === 0))
  await b.shot('stopped-vm-page.png')
  await b.page.setViewport(PHONE)
  check('the stopped VM page does not scroll sideways on a phone', await noSidewaysScroll(b))
  await b.shot('stopped-vm-page-phone.png', true)
  await b.page.setViewport(DESKTOP)
}

async function otherVmPages(b: Browse): Promise<void> {
  await vmPage(b, 'w-evil', 'evil')
  const shown = await whyText(b)
  const harmless = await b.run((img) => ({
    xss: Reflect.get(window, '__xss') ?? 0,
    injected: document.querySelectorAll('.tabbody .why img, .tabbody .why script').length,
    literal: (document.querySelector<HTMLElement>('.tabbody .why code')?.textContent ?? '').includes(img),
  }), HOSTILE_IMG)
  check('hostile log lines stay text: nothing ran and nothing was injected', harmless.xss === 0 && harmless.injected === 0 && harmless.literal, JSON.stringify(harmless))
  check('colour codes and control characters from the VM are gone', !shown.includes('\u001b') && !shown.includes('[31m') && shown.includes('colour'), shown)
  check('a reason without an exit code says so', shown.includes('The exit code is not known.'), shown)
  await vmPage(b, 'w-quiet', 'quiet')
  const quietText = await whyText(b)
  check('a stopped VM without a reason that the panel did not stop says it stopped on its own', quietText.includes(QUIET_TEXT) && !quietText.includes('Exit code'), quietText)
  await vmPage(b, 'w-plain', 'plain')
  check('a VM that runs without systemd says so on its page, and a running VM has no stop block', (await b.text()).includes(PLAIN_TEXT) && (await whyText(b)) === '')
}

async function inTheLists(b: Browse): Promise<void> {
  await b.go('#/vms')
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  const rows = (name: string) => b.run((wanted) => [...document.querySelectorAll<HTMLElement>('table[aria-label="VMs"] tbody tr')].find((row) => row.innerText.includes(wanted))?.innerText ?? '', name)
  check('the All VMs row of a VM with a reason has a "Why it stopped" line', /Why it stopped/.test(await rows('test')))
  check('the row of a VM without a reason has none, and a plain VM carries the note about systemd', !/Why it stopped/.test(await rows('quiet')) && (await rows('plain')).includes(PLAIN_TEXT))
  await b.run(() => [...document.querySelectorAll<HTMLElement>('table[aria-label="VMs"] tbody tr')].find((row) => row.innerText.includes('test'))?.querySelector<HTMLElement>('details summary')?.click())
  await b.until(() => document.querySelector('table[aria-label="VMs"] details[open]') !== null, { timeout: SHORT_WAIT_MS })
  check('opening the line shows the exit code and the log lines', /Exit code 255\.[\s\S]*Exiting PID 1/.test(await rows('test')))
  check('a click on the line opens it and does not open the VM page behind the row', b.page.url().endsWith('#/vms'), b.page.url())
  await b.shot('stopped-all-vms.png')
  await b.page.setViewport(PHONE)
  check('All VMs with a reason does not scroll sideways on a phone', await noSidewaysScroll(b))
  await b.shot('stopped-all-vms-phone.png', true)
  await b.page.setViewport(DESKTOP)
  await b.go(`#/machines/details?id=${MACHINE}`)
  await b.until((wanted) => document.querySelector('.phead h1')?.textContent === wanted, { timeout: SHORT_WAIT_MS }, MACHINE)
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  await b.page.waitForSelector('td.c-name a')
  check('the VMs tab of the machine shows the reason in its table too', await b.run(() => document.querySelector('tbody details summary')?.textContent?.trim() === 'Why it stopped'))
  await pickView(b, 'Cards')
  await b.page.waitForSelector('.card')
  check('and in its cards', await b.run(() => document.querySelectorAll('.card details summary').length > 0))
}

const notice = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('.term-box .notice')?.innerText ?? '')

/** The panel's list is a few seconds old: the Terminal button of a VM that has just stopped is still on. */
async function terminalOnAVmThatJustStopped(b: Browse, world: World, token: string): Promise<void> {
  await vmPage(b, 'w-stale', 'stale')
  await b.until(() => [...document.querySelectorAll('.phead button')].some((button) => button.textContent?.trim() === '▸ Web terminal'), { timeout: SHORT_WAIT_MS })
  await sendHeartbeat(world, token, beat([dead, evil, quiet, plain, vm('w-stale', 'stale', 'stopped', { stopped_reason: { exit_code: 255, log_tail: REASON_LOG } })]))
  await b.click('▸ Web terminal')
  await b.until(() => document.querySelector('.term-box .notice') !== null, { timeout: AGENT_WAIT_MS })
  await b.until(() => /Start the VM/.test(document.querySelector<HTMLElement>('.term-box .notice')?.innerText ?? ''), { timeout: AGENT_WAIT_MS })
  const said = await notice(b)
  const header = await b.run(() => document.querySelector<HTMLElement>('.thead')?.innerText ?? '')
  check('a terminal on a VM that has just stopped explains it in the window', said.includes('This VM has stopped, so there is nothing to connect to.'), said)
  check('it never shows "error · the VM is not running"', !BROKEN_ERROR.test(header) && !BROKEN_ERROR.test(said), header)
  check('it shows the reason (exit code and log lines) in the window', said.includes('Exit code 255.') && said.includes('Failed to mount API filesystems.'), said)
  check('it offers Start the VM and Close', said.includes('Start the VM') && said.includes('Close'))
  await b.shot('stopped-terminal-window.png')
  await b.page.setViewport(PHONE)
  check('the window does not scroll sideways on a phone', await noSidewaysScroll(b) && await b.run(() => { const box = document.querySelector('.term-box'); return box !== null && box.getBoundingClientRect().right <= window.innerWidth }))
  await b.shot('stopped-terminal-window-phone.png')
  await b.page.setViewport(DESKTOP)
  await b.click('Close')
  await b.until(() => document.querySelector('.term-box') === null, { timeout: SHORT_WAIT_MS })
}

async function stopFromOutside(world: World, vmId: string): Promise<void> {
  if (!world.session) throw new Error('seed the world first')
  const url = `${world.root.base}/api/machines/${AGENT_MACHINE}/workloads/${vmId}/stop`
  const reply = await fetch(url, { method: 'POST', headers: writeHeaders(world.root.base, world.session) })
  check('the stop order is accepted', reply.status === 202, String(reply.status))
}

/** The id the machine gave a VM, once the machine has reported it (the order succeeds a little before that). */
async function theVmIdOf(world: World, name: string): Promise<string> {
  for (let attempt = 0; attempt < ID_ATTEMPTS; attempt++) {
    const id = await findVmId(world, name)
    if (id) return id
    await wait(ID_PAUSE_MS)
  }
  throw new Error(`no VM ${name} on ${AGENT_MACHINE}`)
}

async function findVmId(world: World, name: string): Promise<string | null> {
  if (!world.session) throw new Error('seed the world first')
  const reply = await fetch(`${world.root.base}/api/machines/${AGENT_MACHINE}`, { headers: { Cookie: world.session.cookie } })
  const body: unknown = await reply.json()
  const workloads = typeof body === 'object' && body !== null && 'workloads' in body && Array.isArray(body.workloads) ? body.workloads : []
  const found = workloads.find((entry: unknown) => typeof entry === 'object' && entry !== null && 'name' in entry && entry.name === name && 'id' in entry && typeof entry.id === 'string')
  return found && typeof found.id === 'string' ? found.id : null
}

/** A real helper: stop the VM under an open terminal, and Start it again from the window. */
async function stoppingUnderAnOpenTerminal(b: Browse, world: World): Promise<void> {
  const agent = await startAgent(world)
  try {
    await b.go('#/machines')
    await b.until(() => document.body.innerText.includes('agent-mac'), { timeout: AGENT_WAIT_MS })
    await b.go(`#/machines/details?id=${AGENT_MACHINE}`)
    await b.until((wanted) => document.querySelector('.phead h1')?.textContent === wanted, { timeout: SHORT_WAIT_MS }, AGENT_MACHINE)
    await createAVm(b, 'under-box')
    const id = await theVmIdOf(world, 'under-box')
    await b.go(`#/machines/details?id=${AGENT_MACHINE}&vm=${id}`)
    await b.until(() => [...document.querySelectorAll('.phead button')].some((button) => button.textContent?.trim() === '▸ Web terminal'), { timeout: AGENT_WAIT_MS })
    await b.click('▸ Web terminal')
    await untilConnected(b)
    await stopFromOutside(world, id)
    await b.until(() => /right after it started/.test(document.querySelector<HTMLElement>('.term-box .notice')?.innerText ?? ''), { timeout: AGENT_WAIT_MS })
    const quick = await notice(b)
    check('when the VM stops within five seconds of opening the window says it stopped right after it started', quick.includes('The VM stopped right after it started.'), quick)
    await b.until(() => /It was stopped\./.test(document.querySelector<HTMLElement>('.term-box .notice')?.innerText ?? ''), { timeout: AGENT_WAIT_MS })
    check('it says the panel stopped it (no reason to look for), and offers Start', (await notice(b)).includes('Start the VM'))
    await b.shot('stopped-terminal-under-open.png')
    await b.click('Start the VM')
    await b.until(() => document.querySelector('.term-box .notice') === null, { timeout: AGENT_WAIT_MS * 2 })
    await untilConnected(b)
    check('Start the VM starts it and the terminal connects again by itself', true)
    await wait(LONG_ENOUGH_MS)
    await stopFromOutside(world, id)
    await b.until(() => /This VM has stopped\./.test(document.querySelector<HTMLElement>('.term-box .notice')?.innerText ?? ''), { timeout: AGENT_WAIT_MS })
    check('a VM that stops under a terminal that was open for a while says "This VM has stopped."', true)
    check('the status line says not connected, not error', /not connected/i.test(await b.run(() => document.querySelector<HTMLElement>('.tstatus')?.innerText ?? '')))
    await b.click('Close')
    await b.until(() => document.querySelector('.term-box') === null, { timeout: SHORT_WAIT_MS })
  } finally {
    agent.kill()
  }
}

export async function stoppedScenario(b: Browse, world: World): Promise<void> {
  if (!world.session) throw new Error('seed the world first')
  const token = await enrollMachine(world, world.session, MACHINE)
  await sendHeartbeat(world, token, beat([dead, evil, quiet, plain, stale]))
  await b.page.reload()
  await b.until(() => document.body.innerText.includes('Overview'), { timeout: AGENT_WAIT_MS })
  await wait(SETTLE_MS)
  await theVmPage(b)
  await resendHeartbeats(world)
  await otherVmPages(b)
  await resendHeartbeats(world)
  await inTheLists(b)
  await resendHeartbeats(world)
  await terminalOnAVmThatJustStopped(b, world, token)
  await stoppingUnderAnOpenTerminal(b, world)
}
