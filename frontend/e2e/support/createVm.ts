// How the browser tests read and drive the Create VM window: its cards are radio groups, so a test looks at the radios (value, checked, disabled, the text they are described by) and clicks the label like a person.
import type { Browse } from './page.ts'

export const NAME = '#vm-create-name'
export const PICKER = '#vm-create-machine'
export const IMAGE_GROUP = 'vm-create-image'
export const SIZE_GROUP = 'vm-create-size'
export const RUNTIME_GROUP = 'vm-create-runtime'
/** The one form of the window; no other page has a form with this name. */
export const CREATE_FORM = 'form[aria-label="Create VM"]'

export interface Card {
  value: string
  checked: boolean
  disabled: boolean
  ariaDisabled: boolean
  /** The words the radio is described by (its caption and its reason). */
  described: string
  /** Everything the card shows. */
  text: string
}

const radios = (group: string) => `dialog[open] input[type=radio][name="${group}"]`

/** The cards of one group, in the order they are shown. */
export const cards = (b: Browse, group: string): Promise<Card[]> =>
  b.page.$$eval(radios(group), (list) =>
    list.flatMap((input) =>
      input instanceof HTMLInputElement
        ? [{
            value: input.value,
            checked: input.checked,
            disabled: input.disabled,
            ariaDisabled: input.getAttribute('aria-disabled') === 'true',
            described: (input.getAttribute('aria-describedby') ?? '').split(' ').map((id) => document.getElementById(id)?.textContent ?? '').join(' ').trim(),
            text: input.closest('label')?.textContent?.trim() ?? '',
          }]
        : [],
    ),
  )

/** "value:on|off" with ":picked" for the checked one, for comparing a whole group at a glance. */
export const summary = (list: Card[]): string[] => list.map((card) => `${card.value}:${card.disabled ? 'off' : 'on'}${card.checked ? ':picked' : ''}`)

/** Clicks the card's label, the way a person clicks the card. */
export const pickCard = (b: Browse, group: string, value: string): Promise<void> =>
  b.run((selector) => {
    const label = document.querySelector(selector)?.closest('label')
    if (!label) throw new Error(`no card ${selector}`)
    label.click()
  }, `${radios(group)}[value="${value}"]`)

/** The value of the picked card of a group, or null. */
export const pickedCard = async (b: Browse, group: string): Promise<string | null> => (await cards(b, group)).find((card) => card.checked)?.value ?? null

/** Sets one of the Custom boxes by its label (CPU, RAM, Disk), the way a person would (the page is told by an input event). */
export const setField = (b: Browse, label: string, value: string): Promise<void> =>
  b.run((wanted, text) => {
    const field = [...document.querySelectorAll('dialog[open] form label')].find((entry) => entry.textContent?.trim().startsWith(wanted))?.querySelector('input')
    if (!field) throw new Error(`no field ${wanted}`)
    field.value = text
    field.dispatchEvent(new Event('input', { bubbles: true }))
  }, label, value)

export const fieldValue = (b: Browse, label: string): Promise<string | null> =>
  b.run((wanted) => [...document.querySelectorAll('dialog[open] form label')].find((entry) => entry.textContent?.trim().startsWith(wanted))?.querySelector('input')?.value ?? null, label)

/** The machine select's value, or null when the window shows no machine select. */
export const pickerValue = (b: Browse): Promise<string | null> => b.run((selector) => document.querySelector<HTMLSelectElement>(selector)?.value ?? null, PICKER)

/** True when the window's Create VM button is switched off. */
export const createDisabled = (b: Browse): Promise<boolean> => b.run(() => [...document.querySelectorAll('dialog[open] form footer button')].find((button) => button.textContent?.trim() === 'Create VM')?.hasAttribute('disabled') ?? true)

/** How many Create VM forms, and how many open dialogs, the page has right now. */
export const createFormCount = (b: Browse): Promise<{ forms: number; openDialogs: number; nameBoxes: number }> =>
  b.run((form) => ({ forms: document.querySelectorAll(form).length, openDialogs: document.querySelectorAll('dialog[open]').length, nameBoxes: document.querySelectorAll('#vm-create-name').length }), CREATE_FORM)

const IMAGES_WAIT_MS = 10000
const UNREADABLE_NOTE = 'could not be read'

/** The window's Image cards have arrived (or the page gave up on the list and said so): a test about to press Create waits for it, the way a person would not click while the form is still moving. */
export const imageListArrived = (b: Browse) =>
  b.until((group, note) => document.querySelectorAll(`input[name="${group}"]`).length > 1 || document.querySelector('dialog[open]')?.textContent?.includes(note) === true, { timeout: IMAGES_WAIT_MS }, IMAGE_GROUP, UNREADABLE_NOTE)
