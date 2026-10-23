// How the browser tests read and drive the Create VM window: its native selects (their lines, which are off, the caption under them) and its three rich dropdowns (server image, install on top, runtime: a button and a list of rows).
import type { Browse } from './page.ts'

const IMAGES_WAIT_MS = 10000
const UNREADABLE_NOTE = 'could not be read'
/** Install on top lists None and the four planned frameworks before the machine's catalog has answered; the catalog's own frameworks come after. */
const ROWS_BEFORE_THE_ANSWER = 5

export const NAME = '#vm-create-name'
export const PICKER = '#vm-create-machine'
export const IMAGE = '#vm-create-image'
export const IMAGE_MENU = '#vm-create-image-menu'
export const FRAMEWORK = '#vm-create-framework'
export const SIZE = '#vm-create-size'
export const RUNTIME = '#vm-create-runtime'
export const GPU = '#vm-create-gpu'
/** The one form of the window; no other page has a form with this name. */
export const CREATE_FORM = 'form[aria-label="Create VM"]'

export interface Line {
  value: string
  text: string
  disabled: boolean
}

/** The lines of one of the window's native selects, in the order they are shown. */
export const lines = (b: Browse, select: string): Promise<Line[]> =>
  b.page.$$eval(`dialog[open] ${select} option`, (list) => list.flatMap((option) => (option instanceof HTMLOptionElement ? [{ value: option.value, text: option.textContent?.trim() ?? '', disabled: option.disabled }] : [])))

/** The value of one of the window's selects, or null when the window has none. */
export const selectValue = (b: Browse, select: string): Promise<string | null> => b.run((selector) => document.querySelector<HTMLSelectElement>(`dialog[open] ${selector}`)?.value ?? null, select)

/** "value:on|off" with ":picked" for the picked one, for comparing a whole select at a glance. */
export async function summary(b: Browse, select: string): Promise<string[]> {
  const picked = await selectValue(b, select)
  return (await lines(b, select)).map((line) => `${line.value}:${line.disabled ? 'off' : 'on'}${line.value === picked ? ':picked' : ''}`)
}

/** Picks a line of a select the way a person does (the page is told by a change event). */
export async function choose(b: Browse, select: string, value: string): Promise<void> {
  const isRich = await b.run((selector) => document.querySelector(`dialog[open] ${selector}`) instanceof HTMLButtonElement, select)
  if (!isRich) return void (await b.page.select(`dialog[open] ${select}`, value))
  await b.page.click(`dialog[open] ${select}`)
  await b.page.click(`dialog[open] ${select}-menu [role=option][data-value="${value}"]`)
}

/** The plain line under a select (its caption), found by the id the select points to. */
export const captionOf = (b: Browse, select: string): Promise<string> =>
  b.run((selector) => document.getElementById(document.querySelector(`dialog[open] ${selector}`)?.getAttribute('aria-describedby') ?? '')?.textContent?.trim() ?? '', select)

export interface ImageRow {
  value: string
  title: string
  caption: string
  text: string
  tag: string
  selected: boolean
  disabled: boolean
  active: boolean
}

export interface ImageState {
  expanded: boolean
  trigger: string
  rows: ImageRow[]
}

/** What a rich dropdown shows right now (the image one unless told otherwise): whether its list is open, the picked row on the button, and every row. */
export const imageState = (b: Browse, trigger: string = IMAGE): Promise<ImageState> =>
  b.run((trigger, menu) => {
    const button = document.querySelector(`dialog[open] ${trigger}`)
    const activeId = button?.getAttribute('aria-activedescendant')
    return {
      expanded: button?.getAttribute('aria-expanded') === 'true',
      trigger: button?.textContent?.replace(/\s+/g, ' ').trim() ?? '',
      rows: [...document.querySelectorAll(`dialog[open] ${menu} [role=option]`)].map((row) => ({
        value: row.getAttribute('data-value') ?? '',
        title: row.querySelector('.name')?.textContent?.trim() ?? '',
        caption: row.querySelector('.caption')?.textContent?.trim() ?? '',
        text: row.textContent?.replace(/\s+/g, ' ').trim() ?? '',
        tag: row.querySelector('.chip')?.textContent?.trim() ?? '',
        selected: row.getAttribute('aria-selected') === 'true',
        disabled: row.getAttribute('aria-disabled') === 'true',
        active: row.id === activeId,
      })),
    }
  }, trigger, `${trigger}-menu`)

/** Clicks a rich dropdown's button to open its list, and reads it. */
export async function openedMenu(b: Browse, trigger: string): Promise<ImageState> {
  await b.page.click(`dialog[open] ${trigger}`)
  return imageState(b, trigger)
}

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

/** The machine's list of images has arrived (or the page gave up on it and said so): a test about to press Create waits for it, the way a person would not click while the form is still moving. */
export const imageListArrived = (b: Browse) =>
  b.until((root, note, before) => Number(document.querySelector(root)?.getAttribute('data-count')) > before || document.querySelector('dialog[open]')?.textContent?.includes(note) === true, { timeout: IMAGES_WAIT_MS }, FRAMEWORK, UNREADABLE_NOTE, ROWS_BEFORE_THE_ANSWER)
