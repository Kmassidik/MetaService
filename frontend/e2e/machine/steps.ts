// The steps of the machine page test: reading the page, the Ruvio switch, and the Save button.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'

export const SHORT_WAIT_MS = 10000
export const COMMAND_WAIT_MS = 15000
const SWITCH = 'button[role=switch]'

export const openMachine = async (b: Browse, base: string, id: string): Promise<void> => {
  await b.page.goto(`${base}/#/machines/details?id=${id}`, { waitUntil: 'networkidle0' })
  await b.until((wanted) => document.querySelector('.phead h1')?.textContent === wanted, { timeout: SHORT_WAIT_MS }, id)
}

/** Opens a tab of the machine page by the start of its label (so "VMs" finds "VMs (2)"). */
export const openTab = async (b: Browse, label: string): Promise<void> => {
  await b.run((wanted) => [...document.querySelectorAll<HTMLElement>('[role=tab]')].find((tab) => tab.textContent?.trim().startsWith(wanted))?.click(), label)
  await b.until((wanted) => document.querySelector('[role=tab][aria-selected=true]')?.textContent?.trim().startsWith(wanted), { timeout: SHORT_WAIT_MS }, label)
}

/** What a field holds, by the id the page gives it (env-<name>). */
export const fieldValue = (b: Browse, name: string) => b.run((id) => document.querySelector<HTMLInputElement>(`#env-${id}`)?.value ?? null, name)

export const fieldError = (b: Browse, name: string) => b.run((id) => document.querySelector<HTMLElement>(`#env-${id}-error`)?.innerText ?? null, name)

/** The row of the Software block with this label, as "label value". */
export const softwareValue = (b: Browse, label: string) =>
  b.run((wanted) => [...document.querySelectorAll<HTMLElement>('section[aria-label=Software] dl > div')].find((row) => row.querySelector('dt')?.textContent === wanted)?.querySelector('dd')?.innerText.trim() ?? null, label)

export const switchState = (b: Browse) => b.run((selector) => {
  const control = document.querySelector<HTMLButtonElement>(selector)
  return control ? { on: control.getAttribute('aria-checked') === 'true', disabled: control.disabled } : null
}, SWITCH)

export const pressSwitch = (b: Browse) => b.page.click(SWITCH)

export const untilSwitch = (b: Browse, on: boolean) =>
  b.until((selector, wanted) => {
    const control = document.querySelector<HTMLButtonElement>(selector)
    return control?.getAttribute('aria-checked') === String(wanted) && !control.disabled
  }, { timeout: COMMAND_WAIT_MS }, SWITCH, on)

export const saveDisabled = (b: Browse) => b.isDisabled('Save')

export async function changeField(b: Browse, name: string, value: string): Promise<void> {
  await b.type(`#env-${name}`, value)
}

export function expectNoSideScroll(b: Browse, where: string) {
  return b.run(() => document.documentElement.scrollWidth <= window.innerWidth).then((ok) => check(`no sideways scrolling: ${where}`, ok))
}
