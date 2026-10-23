// The Terminal button on each VM of the machine page (Building, Table and Cards) and of All VMs: it opens the same window over the page the person is on,
// is switched off with its reason on a stopped VM and on a machine that is not a Mac, and does not open the VM's page from the stretched row link.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from './machines.ts'
import { isOpen, typeLine, untilConnected, untilScreenHas } from './terminal.ts'
import { enrollMachine, resendHeartbeats, sendHeartbeat, type World } from './world.ts'

const MACHINE = 'agent-mac'
const VM = 'term-box'
const STOPPED_MAC = 'mac-stopped'
const STOPPED_VM = 'sleeper'
const NON_MAC_MACHINE = 'dgx-spark'
const NON_MAC_VM = 'demo'
const SHORT_WAIT_MS = 10000
/** The panel reads the machines again every 15 seconds. */
const LIST_WAIT_MS = 20000
const CLOSE_SETTLE_MS = 1500
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }

export interface ButtonFacts { found: boolean; disabled: boolean; label: string }

/** A Terminal button inside the row, card or list item that holds this VM's name. */
const FIND_BUTTON = (scope: string, vm: string) => {
  const holder = [...document.querySelectorAll<HTMLElement>(scope)].find((entry) => entry.innerText.includes(vm))
  const button = holder?.querySelector<HTMLButtonElement>('button[aria-label^="Terminal"]')
  return { found: button !== undefined && button !== null, disabled: button?.disabled ?? false, label: button?.getAttribute('aria-label') ?? '' }
}

export const facts = (b: Browse, scope: string, vm: string): Promise<ButtonFacts> => b.run(FIND_BUTTON, scope, vm)
export const press = (b: Browse, scope: string, vm: string) =>
  b.run((where, name) => [...document.querySelectorAll<HTMLElement>(where)].find((entry) => entry.innerText.includes(name))?.querySelector<HTMLButtonElement>('button[aria-label^="Terminal"]')?.click(), scope, vm)

async function addAStoppedMac(world: World): Promise<void> {
  if (!world.session) throw new Error('seed the world first')
  const token = await enrollMachine(world, world.session, STOPPED_MAC)
  await sendHeartbeat(world, token, {
    facts: { os: 'macos', arch: 'arm64', cpu_cores: 8, ram_total_mb: 16384, disk_total_gb: 500, free_ram_mb: 8000, free_disk_gb: 300, gpu: [], capabilities: { vm: true, container: false, gpu_in_vm: false, gpu_in_container: false }, problems: [] },
    workloads: [{ id: 'wl-s', name: STOPPED_VM, kind: 'vm', state: 'stopped', cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: null, bundle_version: null }],
    bundle_version: null,
  })
}

async function openAndUse(b: Browse, where: string): Promise<void> {
  await b.page.waitForSelector('.term-box .xterm')
  await untilConnected(b)
  await typeLine(b, 'echo from-' + where)
  check(`a terminal opened from ${where} reaches the shell`, new RegExp(`^from-${where}$`, 'm').test(await untilScreenHas(b, new RegExp(`^from-${where}$`, 'm'))))
}

async function closeIt(b: Browse): Promise<void> {
  await b.click('✕ Close')
  await b.until(() => document.querySelector('.term-box') === null, { timeout: SHORT_WAIT_MS })
  await new Promise((done) => setTimeout(done, CLOSE_SETTLE_MS))
}

async function onTheMachinePage(b: Browse): Promise<void> {
  await b.go(`#/machines/details?id=${MACHINE}`)
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, MACHINE)
  await openTab(b, 'VMs')
  await b.page.waitForSelector('.segmented')
  await pickView(b, 'Building')
  await b.page.waitForSelector('.bv-tenants li')
  check('the building view lists the VM with an enabled Terminal button', (await facts(b, '.bv-tenants li', VM)).found && !(await facts(b, '.bv-tenants li', VM)).disabled)
  await pickView(b, 'Cards')
  await b.page.waitForSelector('.card')
  check('the cards view has an enabled Terminal button', (await facts(b, '.card', VM)).found && !(await facts(b, '.card', VM)).disabled)
  await pickView(b, 'Table')
  await b.page.waitForSelector('td.c-name a')
  const row = await facts(b, 'tbody tr', VM)
  check('the table view has an enabled Terminal button for a running VM on a Mac', row.found && !row.disabled && row.label === `Terminal ${VM}`, JSON.stringify(row))
  await press(b, 'tbody tr', VM)
  await openAndUse(b, 'machine-page')
  check('the terminal opens over the machine page, which stays where it was', b.page.url().endsWith(`#/machines/details?id=${MACHINE}`) && /VMs \(\d+\)/.test(await b.text()), b.page.url())
  await b.shot('terminal-from-machine-page.png')
  await closeIt(b)
  check('closing it leaves the machine page', !(await isOpen(b)) && b.page.url().endsWith(`#/machines/details?id=${MACHINE}`))
}

async function inAllVms(b: Browse): Promise<void> {
  await b.go('#/vms')
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  await press(b, 'table[aria-label="VMs"] tbody tr', VM)
  await openAndUse(b, 'all-vms')
  check('a Terminal button in All VMs does not open the VM\'s page behind the row link', b.page.url().endsWith('#/vms'), b.page.url())
  await b.shot('terminal-from-all-vms.png')
  await closeIt(b)
}

async function disabledOnes(b: Browse): Promise<void> {
  await b.go('#/vms')
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  const rows = 'table[aria-label="VMs"] tbody tr'
  await b.until((name) => document.body.innerText.includes(name), { timeout: LIST_WAIT_MS }, STOPPED_VM)
  const stopped = await facts(b, rows, STOPPED_VM)
  check('a stopped VM has a Terminal button that is off and says "VM is stopped"', stopped.found && stopped.disabled && /VM is stopped/.test(stopped.label), JSON.stringify(stopped))
  const notMac = await facts(b, rows, NON_MAC_VM)
  check('a VM on a Linux machine without the terminal flag has a Terminal button that is off and says "Update the helper to use the terminal"', notMac.found && notMac.disabled && /Update the helper to use the terminal/.test(notMac.label), JSON.stringify(notMac))
  await b.shot('terminal-buttons-all-vms.png')
  await b.page.setViewport(PHONE)
  await b.until(() => document.documentElement.scrollWidth <= window.innerWidth, { timeout: SHORT_WAIT_MS })
  check('All VMs with the Terminal buttons has no sideways scrolling on a phone', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await b.shot('terminal-buttons-all-vms-phone.png', true)
  await b.page.setViewport(DESKTOP)
  await b.go(`#/machines/details?id=${NON_MAC_MACHINE}`)
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, NON_MAC_MACHINE)
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  await b.page.waitForSelector('td.c-name a')
  const onMachinePage = await facts(b, 'tbody tr', NON_MAC_VM)
  check('on the machine page of a Linux machine without the flag the Terminal button is off with its reason', onMachinePage.found && onMachinePage.disabled && /Update the helper to use the terminal/.test(onMachinePage.label), JSON.stringify(onMachinePage))
  await b.shot('terminal-buttons-machine-page.png')
  await b.page.setViewport(PHONE)
  await b.shot('terminal-buttons-machine-page-phone.png', true)
  await b.page.setViewport(DESKTOP)
}

export async function terminalButtonsScenario(b: Browse, world: World): Promise<void> {
  await addAStoppedMac(world)
  await resendHeartbeats(world)
  await onTheMachinePage(b)
  await inAllVms(b)
  await resendHeartbeats(world)
  await disabledOnes(b)
}
