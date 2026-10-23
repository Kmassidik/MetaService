// The Create VM window (over All VMs): which machines can be picked and why not, the Container card greyed out on a containers-only machine, the same validation as before,
// the parent's refusal shown with the typed values kept, a VM made on the simulated helper that closes the window and shows up, the old links, Escape and the X, and the machine page's button opening it with its machine locked.
import { check } from '../support/check.ts'
import { CREATE_FORM, NAME, PICKER, SIZE, choose, closeProgress, createDisabled, fieldValue, imageListArrived, lines, pickerValue, selectValue, setField } from '../support/createVm.ts'
import { owlShown } from '../support/owls.ts'
import type { Browse } from '../support/page.ts'
import { createAVm } from '../panel/workloads.ts'
import { CONTAINER_MACHINE, OFFLINE_MACHINE, SICK_MACHINE } from './fleet.ts'
import { crumb, filterValue, heading, openAllVms } from './list.ts'

const SHORT_WAIT_MS = 10000
const HELPER_WAIT_MS = 30000
const MADE_WAIT_MS = 40000
const TOO_MUCH_RAM_GB = '500'
const REFUSED_VM = 'too-big'
const MADE_VM = 'from-page'
const DIALOG_VM = 'dialog-box'
const HELPER_MACHINE = 'agent-mac'
const FOCUS_TRAP_TABS = 14
const FAILURE_LINE = 'dialog[open] .aline.bad'

/** Opens the window through an old Create VM address; All VMs is the page behind it. */
export async function openCreate(b: Browse, hash = '#/vms/create'): Promise<void> {
  await b.go(hash)
  await b.page.waitForSelector('dialog[open]', { timeout: SHORT_WAIT_MS })
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'All VMs', { timeout: SHORT_WAIT_MS })
}

const windowIsOpen = (b: Browse) => b.run(() => document.querySelector('dialog[open]') !== null)
/** True when the address becomes this one within a moment (the window's close event arrives a little after it disappears). */
const addressIs = (b: Browse, hash: string) => b.until((wanted) => location.hash === wanted, { timeout: SHORT_WAIT_MS }, hash).then(() => true, () => false)
export async function closeWithEscape(b: Browse): Promise<void> {
  await b.page.keyboard.press('Escape')
  await closed(b)
  await addressIs(b, '#/vms')
}
const closed = (b: Browse) => b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })
const optionsOf = (b: Browse) => lines(b, PICKER)

export async function noMachinesYet(b: Browse): Promise<void> {
  await openCreate(b)
  check('with no machines the Create VM window sends the person to Find machines', /No machines yet/.test(await b.dialogText()) && (await b.page.$('dialog[open] .empty a[href="#/machines/find"]')) !== null)
  await owlShown(b, 'emptyMachines', 'the Create VM window with no machines')
  await b.shot('vms-create-no-machines.png')
  await b.page.click('dialog[open] .empty a[href="#/machines/find"]')
  await closed(b)
  check('following it closes the window and lands on Find machines', /#\/machines\/find$/.test(b.page.url()))
}

export async function whoCanBePicked(b: Browse): Promise<void> {
  await openCreate(b)
  await b.page.waitForSelector(PICKER)
  const summaryOfOptions = (await optionsOf(b)).map((entry) => `${entry.text}${entry.disabled ? ' [off]' : ''}`)
  const expected = [
    'Choose a machine',
    `${CONTAINER_MACHINE} (containers only) — 400GB free`,
    'dgx-spark (needs setup) — 700GB free [off]',
    'mac-mini (VMs and containers) — 700GB free',
    `${OFFLINE_MACHINE} (offline) [off]`,
    `${SICK_MACHINE} (needs setup) — 400GB free [off]`,
  ]
  check('every machine is listed with what it runs and its free disk; the offline one and the ones needing setup are disabled with their reason; containers-only stays pickable', JSON.stringify(summaryOfOptions) === JSON.stringify(expected), JSON.stringify(summaryOfOptions))
  check('the machine dropdown is a real select with a label, and it has the focus when the window opens', await b.run((selector) => {
    const select = document.querySelector<HTMLSelectElement>(selector)
    return select !== null && select.labels?.length === 1 && document.activeElement === select
  }, PICKER))
  const summaryLine = await b.run(() => document.querySelector('dialog[open] details summary')?.textContent?.trim() ?? '')
  check('the explanations are folded into one collapsed line', summaryLine === "3 machines can't take a VM" && (await b.run(() => document.querySelectorAll('dialog[open] details[open]').length)) === 0, summaryLine)
  await b.page.click('dialog[open] details summary')
  const body = await b.dialogText()
  check('opened, the reasons are written out under the dropdown, with the machine\'s own words', body.includes(`${OFFLINE_MACHINE}: offline`) && body.includes('dgx-spark: needs setup (VMs cannot get an IPv4 address'))
  check('a hostile problem text from a machine is shown as text, not run', body.includes(`${SICK_MACHINE}: needs setup (<img src=x`) && (await b.run(() => window.__xss)) === undefined && (await b.page.$('img[src="x"]')) === null)
  check('nothing is preselected when several machines can take a VM, and Create waits for a machine', (await pickerValue(b)) === '' && (await createDisabled(b)))
  await b.shot('vms-create-offline-disabled.png')
}

export async function preselectedAndValidated(b: Browse): Promise<void> {
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  check('coming from a machine (?machine=) preselects it and puts the cursor in the first control', (await pickerValue(b)) === 'mac-mini' && (await b.run((selector) => document.activeElement === document.querySelector(selector), PICKER)))
  check('with no defaults on the machine the window starts on Medium, Blank and a name box that may stay empty', (await selectValue(b, SIZE)) === 'medium' && !(await createDisabled(b)))
  await openCreate(b, `#/vms/create?machine=${OFFLINE_MACHINE}`)
  await b.page.waitForSelector(PICKER)
  check('an offline machine in the address is not preselected', (await pickerValue(b)) === '' && (await createDisabled(b)))
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.waitForSelector(NAME)
  await b.page.type(NAME, 'Bad Name')
  check('a bad name explains itself and switches Create off', (await createDisabled(b)) && (await b.dialogText()).includes('Use lowercase letters'))
  await b.type(NAME, 'fine-name')
  await choose(b, SIZE, 'custom')
  check('Custom keeps the numbers of what was picked in the boxes', (await fieldValue(b, 'Cores')) === '2' && (await fieldValue(b, 'Memory')) === '4' && (await fieldValue(b, 'Disk')) === '40')
  await setField(b, 'Cores', '65')
  check('a CPU above the limit is refused with the limit', (await createDisabled(b)) && (await b.dialogText()).includes('CPU must be between 1 and 64'))
  await setField(b, 'Cores', '2')
  check('a good form can be sent', !(await createDisabled(b)))
  await b.shot('vms-create-filled.png')
}

/** The window opens from the button on All VMs, closes with Escape and with the X, and the old address is cleaned to plain All VMs. */
export async function openingAndClosing(b: Browse): Promise<void> {
  await openAllVms(b)
  check('All VMs has a green + Create VM button at the top right of its header', await b.run(() => {
    const button = document.querySelector<HTMLElement>('.phead .sp a.btn.green')
    return button !== null && /Create VM/.test(button.innerText) && button.getBoundingClientRect().right > window.innerWidth - 80
  }))
  await b.page.click('.phead .sp a.btn.green')
  await b.page.waitForSelector(CREATE_FORM)
  check('the button opens the window over All VMs, with the machine dropdown focused', (await b.dialogText()).includes('Create VM') && (await b.run((selector) => document.activeElement === document.querySelector(selector), PICKER)))
  await b.page.keyboard.press('Escape')
  await closed(b)
  check('Escape closes it and the address goes back to plain #/vms', await addressIs(b, '#/vms'))
  await openCreate(b, '#/vms/create?machine=mac-mini')
  await b.page.click('dialog[open] button[aria-label=Close]')
  await closed(b)
  check('the X closes it too, also for an old link with a machine in it', await addressIs(b, '#/vms'))
  await openCreate(b)
  for (let step = 0; step < FOCUS_TRAP_TABS; step++) await b.page.keyboard.press('Tab')
  check('the keyboard stays inside the window (focus trap)', await b.run(() => document.querySelector('dialog[open]')?.contains(document.activeElement) ?? false))
  await closeWithEscape(b)
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
  await imageListArrived(b)
  await b.type(NAME, REFUSED_VM)
  await choose(b, SIZE, 'custom')
  await setField(b, 'Memory', TOO_MUCH_RAM_GB)
  await b.click('Create VM')
  await b.page.waitForSelector(FAILURE_LINE, { timeout: SHORT_WAIT_MS })
  const refusal = await b.page.$eval(FAILURE_LINE, (line) => (line instanceof HTMLElement ? line.innerText : ''))
  check('a request that fits nowhere shows the parent\'s numbers inside the window', refusal.includes('needs 512000 MB RAM'), refusal)
  check('the typed values are kept after a refusal', (await b.run((selector) => document.querySelector<HTMLInputElement>(selector)?.value, NAME)) === REFUSED_VM && (await fieldValue(b, 'Memory')) === TOO_MUCH_RAM_GB && (await pickerValue(b)) === HELPER_MACHINE)
  await b.shot('vms-create-refusal.png', true)
  await setField(b, 'Memory', '1')
  await b.type(NAME, MADE_VM)
  await b.click('Create VM')
  await closeProgress(b)
  check('after Create the progress window closes and the address is plain All VMs', (await addressIs(b, '#/vms')) && (await heading(b)) === 'All VMs')
  await b.until((name) => document.body.innerText.includes(name), { timeout: MADE_WAIT_MS }, MADE_VM)
  check('the new VM shows on the page behind (as the Creating card or already as a row)', (await b.text()).includes(MADE_VM))
}

export async function thenInAllVms(b: Browse): Promise<void> {
  await openAllVms(b)
  await b.until((name) => [...document.querySelectorAll('table[aria-label="VMs"] tbody tr')].some((row) => row instanceof HTMLElement && row.innerText.includes(name)), { timeout: MADE_WAIT_MS }, MADE_VM)
  check('the new VM is in All VMs under its machine', (await b.text()).includes(MADE_VM) && (await crumb(b)).includes('4 VMs on 4 machines'), await crumb(b))
  await b.page.select('#vm-machine', HELPER_MACHINE)
  await b.until(() => document.querySelectorAll('table[aria-label="VMs"] tbody tr').length === 1, { timeout: SHORT_WAIT_MS })
  check('filtering to that machine shows only it', (await filterValue(b)) === HELPER_MACHINE)
}

export async function theMachinePageButton(b: Browse): Promise<void> {
  await b.go(`#/machines/details?id=${HELPER_MACHINE}`)
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, HELPER_MACHINE)
  await createAVm(b, DIALOG_VM)
  check('the machine page\'s button uses the same window and closes it after Create, staying on the machine page', !(await windowIsOpen(b)) && b.page.url().endsWith(`#/machines/details?id=${HELPER_MACHINE}`))
  await openAllVms(b)
  await b.until((name) => document.body.innerText.includes(name), { timeout: MADE_WAIT_MS }, DIALOG_VM)
  check('a VM made with the button on the machine\'s page shows in All VMs', (await b.text()).includes(DIALOG_VM))
}
