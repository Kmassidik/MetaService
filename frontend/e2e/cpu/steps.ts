// The CPU rows of the Create VM window in a real browser, as in Proxmox's Processors window: Sockets, Cores, Type (a Model and Vendor list) and Total cores for a VM,
// Cores and a CPU limit for a container, the extra CPU flags with Off, Default and On, what the machine cannot set and why, what is sent, and a reset when the machine changes.
import { check } from '../support/check.ts'
import { NAME, PICKER, RUNTIME, SIZE, choose, fieldValue, imageListArrived, selectValue, setField } from '../support/createVm.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { CPU_PC, MAC, MODELS, OLD_PC, TYPES_PC, type CpuStandIn } from './stand-in.ts'

const SHORT_WAIT_MS = 10000
const SENT_TRIES = 50
const SENT_PAUSE_MS = 200
const RAPID_CLICKS = 5
const TYPE = '#vm-create-cpu-type'
const SOCKETS = '#vm-create-sockets'
const LIMIT = '#vm-create-cpu-limit'
const VENDORS = ['This machine', 'AMD', 'AMD', 'AMD', 'AMD', 'Intel', 'Intel', 'Generic']
const OLD_HELPER_NOTE = "This machine's helper cannot set sockets, the CPU type or CPU flags, so a VM gets the machine's own CPU on one socket. Update the helper to choose them."
const MAC_NOTE = "On a Mac a VM always gets the Mac's own CPU on one socket."
const NO_LIMIT_NOTE = "This machine's helper cannot cap a container's CPU time. Update the helper to set a limit."
const LIMIT_TEXT = 'CPU limit must be between 0.1 and 2 cores, or empty for no limit.'
const REFUSAL_TEXT = 'This machine cannot set the CPU type EPYC-Genoa. Update its helper, or pick host.'
const CPU_KEYS = ['cpu_sockets', 'cpu_type', 'cpu_flags', 'cpu_limit_percent']

/** A fresh Create VM window on one machine: leave for the list first, so an open window and its choices are not kept. */
export async function openCreate(b: Browse, base: string, machine: string): Promise<void> {
  await b.page.goto(`${base}/#/vms`, { waitUntil: 'networkidle0' })
  await b.page.goto(`${base}/#/vms/create`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector(`dialog[open] ${PICKER}`, { timeout: SHORT_WAIT_MS })
  await b.page.select(PICKER, machine)
  await b.page.waitForSelector(NAME)
  await imageListArrived(b)
}

async function untilSent(world: CpuStandIn, count: number): Promise<void> {
  for (let tries = 0; tries < SENT_TRIES && world.created.length < count; tries++) await wait(SENT_PAUSE_MS)
}

/** After a good Create the form goes; the progress window may follow, so close whatever is left open. */
async function waitForClosed(b: Browse): Promise<void> {
  await b.until(() => document.querySelector('dialog[open] form[aria-label="Create VM"]') === null, { timeout: SHORT_WAIT_MS })
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
}

/** What the CPU rows show right now. */
const cpuState = (b: Browse) =>
  b.run((type, sockets) => {
    const typeBox = document.querySelector<HTMLButtonElement>(`dialog[open] ${type}`)
    const socketsBox = document.querySelector<HTMLInputElement>(`dialog[open] ${sockets}`)
    const flags = [...document.querySelectorAll('dialog[open] tr[data-flag]')].map((row) => ({
      flag: row.getAttribute('data-flag'),
      lit: row.querySelector('label.on')?.getAttribute('data-setting') ?? null,
      off: row.querySelector<HTMLInputElement>('input')?.disabled ?? null,
      where: row.querySelector('.where')?.textContent?.trim() ?? '',
    }))
    return {
      type: typeBox?.querySelector('.value')?.textContent?.trim() ?? null,
      typeOff: typeBox?.disabled ?? null,
      clear: document.querySelector('dialog[open] .combo .clear') !== null,
      sockets: socketsBox?.value ?? null,
      socketsOff: socketsBox?.disabled ?? null,
      total: document.querySelector('dialog[open] [data-total-cores]')?.textContent?.trim() ?? null,
      note: document.querySelector('dialog[open] [data-cpu-note]')?.textContent?.trim() ?? null,
      flags,
    }
  }, TYPE, SOCKETS)

const createDisabled = (b: Browse) => b.isDisabled('Create VM')
const pickFlag = (b: Browse, flag: string, setting: string) => b.page.click(`dialog[open] tr[data-flag="${flag}"] label[data-setting="${setting}"]`)
const cpuKeys = (body: Record<string, unknown> | undefined) => CPU_KEYS.filter((key) => body !== undefined && key in body)

/** The rows of a VM on a machine that offers everything, and the Type list with its Model and Vendor columns, driven by the keys. */
export async function rowsAndTypeList(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, CPU_PC)
  const start = await cpuState(b)
  check('a VM starts on one socket, the host CPU, every flag on Default and no note', start.sockets === '1' && !start.socketsOff && start.type === 'host' && !start.typeOff && !start.clear && start.total === '2' && start.note === null && start.flags.every((row) => row.lit === 'default' && row.off === false), JSON.stringify(start))
  await b.page.focus(TYPE)
  await b.page.keyboard.press('ArrowDown')
  await b.page.waitForSelector(`dialog[open] ${TYPE}-menu`)
  const list = await b.run((menu) => ({
    head: [...document.querySelectorAll(`dialog[open] ${menu} .head span`)].map((cell) => cell.textContent?.trim()),
    models: [...document.querySelectorAll(`dialog[open] ${menu} [role=option] .model`)].map((cell) => cell.textContent?.trim()),
    vendors: [...document.querySelectorAll(`dialog[open] ${menu} [role=option] .vendor`)].map((cell) => cell.textContent?.trim()),
    picked: document.querySelector(`dialog[open] ${menu} [aria-selected=true]`)?.getAttribute('data-value'),
  }), `${TYPE}-menu`)
  check('the Type list has a Model and a Vendor column, host first, and only the models the machine offers', JSON.stringify(list.head) === '["Model","Vendor"]' && JSON.stringify(list.models) === JSON.stringify(MODELS) && JSON.stringify(list.vendors) === JSON.stringify(VENDORS) && list.picked === 'host', JSON.stringify(list))
  await b.shot('cpu-type-list.png')
  for (let step = 0; step < MODELS.indexOf('EPYC-Genoa'); step++) await b.page.keyboard.press('ArrowDown')
  await b.page.keyboard.press('Enter')
  const picked = await cpuState(b)
  check('the arrow keys and Enter pick EPYC-Genoa, shut the list, and the × to go back to host appears', picked.type === 'EPYC-Genoa' && picked.clear && (await b.run((menu) => document.querySelector(`dialog[open] ${menu}`) === null, `${TYPE}-menu`)), JSON.stringify(picked))
  await b.page.keyboard.press('ArrowDown')
  await b.page.keyboard.press('Escape')
  check('Escape shuts only the list, never the window, and keeps EPYC-Genoa', (await b.run(() => document.querySelector('dialog[open] form') !== null)) && (await cpuState(b)).type === 'EPYC-Genoa')
  await b.page.click('dialog[open] .combo .clear')
  const back = await cpuState(b)
  check('the × goes back to host and goes away', back.type === 'host' && !back.clear, JSON.stringify(back))
  await b.page.keyboard.press('Escape')
}

/** Sockets times cores is the total; typing moves the size to Custom; the arrows step the numbers. */
export async function socketsAndCores(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, CPU_PC)
  await setField(b, 'Sockets', '2')
  check('two sockets keep the cores per socket and double the total', (await fieldValue(b, 'Cores')) === '2' && (await cpuState(b)).total === '4')
  await setField(b, 'Cores', '4')
  check('4 cores on 2 sockets is 8 in total, and the size moves to Custom', (await cpuState(b)).total === '8' && (await selectValue(b, SIZE)) === 'custom')
  await b.page.click(`dialog[open] .spin:has(${SOCKETS}) button[aria-label="Up"]`)
  check('the up arrow next to Sockets makes 3 sockets, 12 in total', (await fieldValue(b, 'Sockets')) === '3' && (await cpuState(b)).total === '12')
  await setField(b, 'Sockets', '9')
  check('more than 8 sockets is refused in plain words and Create waits', (await b.dialogText()).includes('Sockets must be a whole number from 1 to 8.') && (await createDisabled(b)))
  await choose(b, SIZE, 'medium')
  const medium = await cpuState(b)
  check('a preset goes back to one socket with its own numbers', medium.sockets === '1' && medium.total === '2' && !(await createDisabled(b)), JSON.stringify(medium))
  await b.shot('cpu-sockets-cores.png')
  await b.page.keyboard.press('Escape')
}

/** The flags table: Default lit until a button is pressed, Supported on names the machines whose helper can switch the flag. */
export async function flagsTable(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, CPU_PC)
  const start = await cpuState(b)
  check('Supported on names the machines that can switch each flag', JSON.stringify(start.flags.map((row) => [row.flag, row.where])) === JSON.stringify([['nested-virt', CPU_PC], ['aes', `${CPU_PC}, ${TYPES_PC}`]]), JSON.stringify(start.flags))
  await pickFlag(b, 'nested-virt', 'off')
  await pickFlag(b, 'aes', 'on')
  const lit = await cpuState(b)
  check('Off and On light up where they were pressed', lit.flags[0]?.lit === 'off' && lit.flags[1]?.lit === 'on', JSON.stringify(lit.flags))
  await pickFlag(b, 'aes', 'default')
  check('Default lights up again', (await cpuState(b)).flags[1]?.lit === 'default')
  await b.shot('cpu-flags.png')
  await b.page.keyboard.press('Escape')
}

/** The order carries the CPU choices with the contract's names, once for rapid clicks. */
export async function sendsTheChoices(b: Browse, world: CpuStandIn): Promise<void> {
  await openCreate(b, world.base, CPU_PC)
  await b.type(NAME, 'genoa-box')
  await setField(b, 'Sockets', '2')
  await setField(b, 'Cores', '4')
  await b.page.click(TYPE)
  await b.page.click(`dialog[open] ${TYPE}-menu [data-value="EPYC-Genoa"]`)
  await pickFlag(b, 'nested-virt', 'off')
  await pickFlag(b, 'aes', 'on')
  const before = world.created.length
  await b.run((times) => {
    const button = [...document.querySelectorAll('dialog[open] form footer button')].find((entry) => entry.textContent?.trim() === 'Create VM')
    if (!(button instanceof HTMLButtonElement)) throw new Error('no Create VM button')
    for (let press = 0; press < times; press++) button.click()
  }, RAPID_CLICKS)
  await untilSent(world, before + 1)
  await waitForClosed(b)
  await wait(SENT_PAUSE_MS)
  const sent = world.created[before]
  check(`${RAPID_CLICKS} quick clicks send ONE order`, world.created.length === before + 1, `${world.created.length - before}`)
  check('the order has 8 CPUs on 2 sockets, the EPYC-Genoa type and the two flags, with the contract\'s names', sent?.cpu === 8 && sent.cpu_sockets === 2 && sent.cpu_type === 'EPYC-Genoa' && JSON.stringify(sent.cpu_flags) === '{"nested-virt":"off","aes":"on"}' && !('cpu_limit_percent' in sent), JSON.stringify(sent))
}

/** With nothing touched every machine gets exactly the order it got before. */
export async function sendsTheOldBodies(b: Browse, world: CpuStandIn): Promise<void> {
  for (const [machine, kind] of [[CPU_PC, 'vm'], [CPU_PC, 'container'], [OLD_PC, 'vm'], [MAC, 'vm']] as const) {
    await openCreate(b, world.base, machine)
    if (kind === 'container') await choose(b, RUNTIME, 'container')
    const before = world.created.length
    await b.click('Create VM')
    await untilSent(world, before + 1)
    await waitForClosed(b)
    const sent = world.created[before]
    check(`${machine}, ${kind} with nothing touched: no CPU keys in the order`, sent !== undefined && cpuKeys(sent).length === 0 && sent.kind === kind, JSON.stringify(sent))
  }
}

/** A container gets Cores and a CPU limit instead of sockets, type and flags; the limit is sent in percent of one core and checked as it is typed. */
export async function containerLimit(b: Browse, world: CpuStandIn): Promise<void> {
  await openCreate(b, world.base, CPU_PC)
  await choose(b, RUNTIME, 'container')
  const rows = await b.run((type, sockets, limit) => ({ type: document.querySelector(`dialog[open] ${type}`) !== null, sockets: document.querySelector(`dialog[open] ${sockets}`) !== null, flags: document.querySelector('dialog[open] [data-cpu-flags]') !== null, placeholder: document.querySelector<HTMLInputElement>(`dialog[open] ${limit}`)?.placeholder ?? null }), TYPE, SOCKETS, LIMIT)
  check('a container has no Sockets, Type or flags, and an empty CPU limit that says unlimited', !rows.type && !rows.sockets && !rows.flags && rows.placeholder === 'unlimited', JSON.stringify(rows))
  await setField(b, 'CPU limit', '3')
  check('a limit above the cores is refused in plain words and Create waits', (await b.dialogText()).includes(LIMIT_TEXT) && (await createDisabled(b)))
  await setField(b, 'CPU limit', '1.5')
  await b.shot('cpu-container-limit.png')
  const before = world.created.length
  await b.click('Create VM')
  await untilSent(world, before + 1)
  await waitForClosed(b)
  const sent = world.created[before]
  check('1.5 cores is sent as cpu_limit_percent 150, and nothing for a VM', sent?.kind === 'container' && sent.cpu_limit_percent === 150 && !('cpu_sockets' in sent) && !('cpu_type' in sent) && !('cpu_flags' in sent), JSON.stringify(sent))
}

/** What the machine cannot set is off, with one plain line saying why: an older helper, a Mac, and a machine that offers part of it. */
export async function whatMachinesCannotSet(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, OLD_PC)
  const old = await cpuState(b)
  check('an older helper: Sockets and Type are off, every flag is off, and the note says to update the helper', old.socketsOff === true && old.typeOff === true && old.type === 'host' && old.flags.every((row) => row.off === true && row.lit === 'default') && old.note === OLD_HELPER_NOTE, JSON.stringify(old))
  await b.shot('cpu-old-helper.png')
  await choose(b, RUNTIME, 'container')
  const limitOff = await b.run((limit) => document.querySelector<HTMLInputElement>(`dialog[open] ${limit}`)?.disabled ?? null, LIMIT)
  check('an older helper: the CPU limit is off and the note says why', limitOff === true && (await cpuState(b)).note === NO_LIMIT_NOTE)
  await b.page.keyboard.press('Escape')
  await openCreate(b, base, MAC)
  check('a Mac says in its own words that a VM gets the Mac\'s own CPU on one socket', (await cpuState(b)).note === MAC_NOTE)
  await b.page.keyboard.press('Escape')
  await openCreate(b, base, TYPES_PC)
  const part = await cpuState(b)
  check('a machine that offers a type and aes only: one socket, host or EPYC, aes open, nested-virt off, and no note', part.socketsOff === true && part.typeOff === false && part.note === null && part.flags[0]?.off === true && part.flags[1]?.off === false, JSON.stringify(part))
  await b.page.click(TYPE)
  const models = await b.run((menu) => [...document.querySelectorAll(`dialog[open] ${menu} [role=option]`)].map((row) => row.getAttribute('data-value')), `${TYPE}-menu`)
  check('its Type list is host and EPYC', JSON.stringify(models) === '["host","EPYC"]', JSON.stringify(models))
  await b.page.keyboard.press('Escape')
  await b.page.keyboard.press('Escape')
}

/** Another machine takes away what it does not offer; what it does offer stays. */
export async function machineChangeResets(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, CPU_PC)
  await setField(b, 'Sockets', '2')
  await b.page.click(TYPE)
  await b.page.click(`dialog[open] ${TYPE}-menu [data-value="EPYC-Genoa"]`)
  await pickFlag(b, 'nested-virt', 'off')
  await pickFlag(b, 'aes', 'on')
  await b.page.select(PICKER, TYPES_PC)
  await imageListArrived(b)
  const moved = await cpuState(b)
  check('on a machine without sockets or EPYC-Genoa they go back to 1 and host, nested-virt goes back to Default, aes stays On', moved.sockets === '1' && moved.type === 'host' && moved.flags[0]?.lit === 'default' && moved.flags[1]?.lit === 'on', JSON.stringify(moved))
  await b.page.keyboard.press('Escape')
}

/** The ↺ in the title bar puts the window back as it opened. */
export async function resetButton(b: Browse, base: string): Promise<void> {
  await openCreate(b, base, CPU_PC)
  await b.type(NAME, 'about-to-go')
  await setField(b, 'Sockets', '2')
  await pickFlag(b, 'aes', 'on')
  await b.page.click('dialog[open] .modal-tool[aria-label="Reset"]')
  await b.page.waitForSelector(NAME)
  const after = await cpuState(b)
  const name = await b.run((selector) => document.querySelector<HTMLInputElement>(selector)?.value, NAME)
  check('Reset empties the name, goes back to one socket, Medium and Default, and keeps the window open', name === '' && after.sockets === '1' && after.flags.every((row) => row.lit === 'default') && (await selectValue(b, SIZE)) === 'medium', JSON.stringify({ name, after }))
  await b.page.keyboard.press('Escape')
}

/** A refusal from the parent shows inside the window, and the choices stay as they were. */
export async function serverRefusalStaysInTheModal(b: Browse, world: CpuStandIn): Promise<void> {
  await openCreate(b, world.base, CPU_PC)
  await b.page.click(TYPE)
  await b.page.click(`dialog[open] ${TYPE}-menu [data-value="EPYC-Genoa"]`)
  world.refuseNext(409, { code: 'missing_capability', message: REFUSAL_TEXT })
  await b.click('Create VM')
  await b.until((text) => document.querySelector('dialog[open]')?.textContent?.includes(text) === true, { timeout: SHORT_WAIT_MS }, REFUSAL_TEXT)
  check('the parent\'s refusal shows inside the window and EPYC-Genoa stays picked', (await cpuState(b)).type === 'EPYC-Genoa')
  await b.page.keyboard.press('Escape')
}
