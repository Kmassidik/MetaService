// The Create VM page: which machines can be picked and why not, the VM kind switched off on a containers-only machine, the same validation as the old dialog,
// the parent's refusal shown with the typed values kept, a VM made on the simulated helper that lands on its page, and the old dialog still working.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { createAVm } from '../panel/workloads.ts'
import { CONTAINER_MACHINE, OFFLINE_MACHINE, SICK_MACHINE } from './fleet.ts'
import { crumb, filterValue, openAllVms } from './list.ts'

const SHORT_WAIT_MS = 10000
const HELPER_WAIT_MS = 30000
const MADE_WAIT_MS = 40000
const PICKER = '#vm-create-machine'
const NAME = '#vm-create-name'
const TOO_MUCH_RAM_GB = '500'
const REFUSED_VM = 'too-big'
const MADE_VM = 'from-page'
const DIALOG_VM = 'dialog-box'
const HELPER_MACHINE = 'agent-mac'

interface Choice { value: string; text: string; disabled: boolean }

const choices = (b: Browse): Promise<Choice[]> => b.page.$$eval(`${PICKER} option`, (list) => list.flatMap((option) => (option instanceof HTMLOptionElement ? [{ value: option.value, text: option.textContent?.trim() ?? '', disabled: option.disabled }] : [])))
const pickerValue = (b: Browse) => b.run((selector) => document.querySelector<HTMLSelectElement>(selector)?.value ?? null, PICKER)
const createDisabled = (b: Browse) => b.run(() => [...document.querySelectorAll('main form button[type=submit]')].every((button) => button instanceof HTMLButtonElement && button.disabled))

/** Sets one of the size fields by its label, the way a person would (the page is told by an input event). */
const setField = (b: Browse, label: string, value: string) =>
  b.run((wanted, text) => {
    const field = [...document.querySelectorAll<HTMLElement>('main form label')].find((entry) => entry.innerText.startsWith(wanted))?.querySelector('input')
    if (!field) throw new Error(`no field ${wanted}`)
    field.value = text
    field.dispatchEvent(new Event('input', { bubbles: true }))
  }, label, value)

const fieldValue = (b: Browse, label: string) => b.run((wanted) => [...document.querySelectorAll<HTMLElement>('main form label')].find((entry) => entry.innerText.startsWith(wanted))?.querySelector('input')?.value ?? null, label)

export async function openCreate(b: Browse, hash = '#/vms/create'): Promise<void> {
  await b.go(hash)
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Create VM', { timeout: SHORT_WAIT_MS })
}

export async function noMachinesYet(b: Browse): Promise<void> {
  await openCreate(b)
  check('with no machines Create VM sends the person to Find machines', /No machines yet/.test(await b.text()) && (await b.page.$('.empty a[href="#/machines/find"]')) !== null)
  await b.shot('vms-create-no-machines.png')
}

export async function whoCanBePicked(b: Browse): Promise<void> {
  await openCreate(b)
  await b.page.waitForSelector(PICKER)
  const list = await choices(b)
  const summary = list.map((entry) => `${entry.text}${entry.disabled ? ' [off]' : ''}`)
  const expected = ['Choose a machine', `${CONTAINER_MACHINE} (containers only)`, 'dgx-spark (needs setup) [off]', 'mac-mini', `${OFFLINE_MACHINE} (offline) [off]`, `${SICK_MACHINE} (needs setup) [off]`]
  check('every machine is listed by name; the offline one and the one needing setup are disabled with their reason; containers-only stays pickable', JSON.stringify(summary) === JSON.stringify(expected), JSON.stringify(summary))
  const body = await b.text()
  check('the reasons are also written out under the dropdown, with the machine\'s own words', body.includes(`${OFFLINE_MACHINE}: offline`) && body.includes('dgx-spark: needs setup (VMs cannot get an IPv4 address'))
  check('a hostile problem text from a machine is shown as text, not run', body.includes(`${SICK_MACHINE}: needs setup (<img src=x`) && (await b.run(() => window.__xss)) === undefined && (await b.page.$('img[src="x"]')) === null)
  check('nothing is preselected and step 2 waits for a machine', (await pickerValue(b)) === '' && (await b.page.$(NAME)) === null && /1 · machine/i.test(await b.text()))
  await b.shot('vms-create-offline-disabled.png')
}

export async function kindsOnAMachine(b: Browse): Promise<void> {
  await b.page.select(PICKER, CONTAINER_MACHINE)
  await b.page.waitForSelector(NAME)
  const kinds = await b.page.$$eval('main form select:not(#vm-create-machine) option', (list) => list.flatMap((option) => (option instanceof HTMLOptionElement ? [`${option.value}:${option.disabled}`] : [])))
  const kind = await b.run(() => document.querySelector<HTMLSelectElement>('main form select:not(#vm-create-machine)')?.value)
  check('on a containers-only machine the VM kind is disabled and Container is chosen', JSON.stringify(kinds) === JSON.stringify(['vm:true', 'container:false']) && kind === 'container', JSON.stringify(kinds) + kind)
  await b.shot('vms-create-containers-only.png')
}

export async function preselectedAndValidated(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  check('coming from a machine (?machine=) preselects it and shows step 2', (await pickerValue(b)) === 'mac-mini')
  await openCreate(b, `#/vms/create?machine=${OFFLINE_MACHINE}`)
  await b.page.waitForSelector(PICKER)
  check('an offline machine in the address is not preselected', (await pickerValue(b)) === '' && (await b.page.$(NAME)) === null)
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  await b.page.type(NAME, 'Bad Name')
  check('a bad name explains itself and switches Create off, as in the dialog', (await createDisabled(b)) && (await b.text()).includes('Use lowercase letters'))
  await setField(b, 'CPU', '65')
  await b.type(NAME, 'fine-name')
  check('a CPU above the limit is refused with the limit', (await createDisabled(b)) && (await b.text()).includes('CPU must be between 1 and 64'))
  await setField(b, 'CPU', '2')
  check('a good form can be sent', !(await createDisabled(b)))
}

async function waitForHelper(b: Browse): Promise<void> {
  await b.until((id) => document.body.innerText.length > 0 && [...document.querySelectorAll<HTMLOptionElement>('#vm-create-machine option')].some((option) => option.value === id && !option.disabled), { timeout: HELPER_WAIT_MS }, HELPER_MACHINE)
}

export async function refusedThenMade(b: Browse): Promise<void> {
  await openCreate(b)
  await b.page.waitForSelector(PICKER)
  await waitForHelper(b)
  await b.page.select(PICKER, HELPER_MACHINE)
  await b.page.waitForSelector(NAME)
  await b.type(NAME, REFUSED_VM)
  await setField(b, 'RAM', TOO_MUCH_RAM_GB)
  await b.click('Create')
  await b.page.waitForSelector('main form [role=alert]', { timeout: SHORT_WAIT_MS })
  const refusal = await b.page.$eval('main form [role=alert]', (alert) => (alert instanceof HTMLElement ? alert.innerText : ''))
  check('a request that fits nowhere shows the parent\'s numbers', refusal.includes('needs 512000 MB RAM'), refusal)
  check('the typed values are kept after a refusal', (await b.run((selector) => document.querySelector<HTMLInputElement>(selector)?.value, NAME)) === REFUSED_VM && (await fieldValue(b, 'RAM')) === TOO_MUCH_RAM_GB && (await pickerValue(b)) === HELPER_MACHINE)
  await b.shot('vms-create-refusal.png', true)
  await setField(b, 'RAM', '1')
  await b.type(NAME, MADE_VM)
  await b.click('Create')
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: MADE_WAIT_MS }, MADE_VM)
  check('creating a VM here ends on that VM\'s own page', /#\/machines\/details\?id=agent-mac&vm=[A-Za-z0-9_-]+$/.test(b.page.url()), b.page.url())
}

export async function thenInAllVms(b: Browse): Promise<void> {
  await openAllVms(b)
  await b.until((name) => document.body.innerText.includes(name), { timeout: SHORT_WAIT_MS }, MADE_VM)
  check('the new VM is in All VMs under its machine', (await b.text()).includes(MADE_VM) && (await crumb(b)).includes('4 VMs on 4 machines'), await crumb(b))
  await b.page.select('#vm-machine', HELPER_MACHINE)
  await b.until(() => document.querySelectorAll('table[aria-label="VMs"] tbody tr').length === 1, { timeout: SHORT_WAIT_MS })
  check('filtering to that machine shows only it', (await filterValue(b)) === HELPER_MACHINE)
}

export async function theOldButtonStillWorks(b: Browse): Promise<void> {
  await b.go(`#/machines/details?id=${HELPER_MACHINE}`)
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, HELPER_MACHINE)
  await createAVm(b, DIALOG_VM)
  await openAllVms(b)
  await b.until((name) => document.body.innerText.includes(name), { timeout: MADE_WAIT_MS }, DIALOG_VM)
  check('a VM made with the button on the machine\'s page still works and shows in All VMs', (await b.text()).includes(DIALOG_VM))
}
