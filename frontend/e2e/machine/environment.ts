// The Environment tab's collapsible rows and its save bar, as a person sees them.
import type { Page } from 'puppeteer-core'
import { SHORT_WAIT_MS, changeField, expectNoSideScroll, fieldValue } from './steps.ts'
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'

const BAR = '[aria-label="Save bar"]'
const ROW = '.env section[aria-label]'
const SAVED_LINE_MS = 2000
const SAME_PIXEL = 1
const RAPID_CLICKS = 5
const PHONE = { width: 400, height: 844 }
const LAPTOP = { width: 1280, height: 800 }
/** A summary is one line when it is shorter than this (the text is 12px; two lines would be about 36px). */
const ONE_LINE_MAX_PX = 24
const TWO_LINES_MAX_PX = 44
const ROW_TITLES = 'This machine|Software|Ruvio|Limits|A new VM gets|Names'
const INVALID_CPU = '65'

export interface RowState {
  title: string
  expanded: boolean
  controls: string
  bodyHidden: boolean
  summary: string
  summaryHeight: number
  headerBottom: number
  changed: boolean
  error: boolean
}

export const barShown = (b: Browse) => b.run((selector) => !!document.querySelector(selector), BAR)

export const barText = (b: Browse) => b.run((selector) => document.querySelector<HTMLElement>(selector)?.innerText ?? '', BAR)

/** Every row as it looks now, top to bottom. */
export const rowStates = (b: Browse): Promise<RowState[]> => b.run((rowSelector) => [...document.querySelectorAll(rowSelector)].map((row) => {
  const head = row.querySelector<HTMLButtonElement>('button.trigger')
  const summary = row.querySelector<HTMLElement>('.summary')
  const body = row.querySelector<HTMLElement>('.body')
  return {
    title: row.getAttribute('aria-label') ?? '',
    expanded: head?.getAttribute('aria-expanded') === 'true',
    controls: head?.getAttribute('aria-controls') ?? '',
    bodyHidden: body?.hidden === true,
    summary: summary?.innerText.trim() ?? '',
    summaryHeight: summary?.getBoundingClientRect().height ?? -1,
    headerBottom: head?.getBoundingClientRect().bottom ?? -1,
    changed: row.querySelector('.dot') !== null,
    error: row.querySelector('.badge') !== null,
  }
}), ROW)

const rowNamed = async (b: Browse, title: string): Promise<RowState> => {
  const row = (await rowStates(b)).find((state) => state.title === title)
  if (!row) throw new Error(`there is no row "${title}"`)
  return row
}

const openTitles = async (b: Browse) => (await rowStates(b)).filter((row) => row.expanded).map((row) => row.title).join('|')

/** Presses the header of the row with this title. */
export const pressHeader = (b: Browse, title: string) =>
  b.run((rowSelector, wanted) => document.querySelector<HTMLButtonElement>(`${rowSelector}[aria-label="${wanted}"] button.trigger`)?.click(), ROW, title)

/** Opens the row when it is closed, so its fields can be typed into. */
export async function openRow(b: Browse, title: string): Promise<void> {
  if (!(await rowNamed(b, title)).expanded) await pressHeader(b, title)
  await b.until((rowSelector, wanted) => document.querySelector<HTMLElement>(`${rowSelector}[aria-label="${wanted}"] .body`)?.hidden === false, { timeout: SHORT_WAIT_MS }, ROW, title)
}

const pressExpandAll = (b: Browse) => b.run(() => [...document.querySelectorAll<HTMLButtonElement>('.env .expand')].forEach((button) => button.click()))
const expandAllLabel = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('.env .expand')?.innerText.trim() ?? '')

/** Opens every row with the link above the rows. */
export async function expandAll(b: Browse): Promise<void> {
  if ((await expandAllLabel(b)) === 'Expand all') await pressExpandAll(b)
  await b.until(() => [...document.querySelectorAll('.env section[aria-label] button.trigger')].every((head) => head.getAttribute('aria-expanded') === 'true'), { timeout: SHORT_WAIT_MS })
}

const summaryOf = async (b: Browse, title: string) => (await rowNamed(b, title)).summary

/** Fresh page: six rows in order, all closed, each with a one-line summary made of the machine's real values, all headers above the fold. */
export async function rowsAtFirst(page: Page, b: Browse): Promise<void> {
  await page.setViewport(LAPTOP)
  await b.until((rowSelector) => document.querySelectorAll(rowSelector).length === 6 && !/loading/.test(document.querySelector('.env')?.textContent ?? ''), { timeout: SHORT_WAIT_MS }, ROW)
  const rows = await rowStates(b)
  check('the Environment tab has six rows in order', rows.map((row) => row.title).join('|') === ROW_TITLES, rows.map((row) => row.title).join('|'))
  check('every row starts closed, with its body hidden and tied to its header', rows.every((row) => !row.expanded && row.bodyHidden && row.controls !== ''), JSON.stringify(rows.map((row) => [row.expanded, row.bodyHidden])))
  check('every row has a one-line summary', rows.every((row) => row.summary !== '' && row.summaryHeight > 0 && row.summaryHeight <= ONE_LINE_MAX_PX), JSON.stringify(rows.map((row) => [row.summary, row.summaryHeight])))
  check('no summary says undefined or null', rows.every((row) => !/undefined|null|NaN/.test(row.summary)))
  check('This machine says state, cores, memory and system', (await summaryOf(b, 'This machine')) === 'online · 14 cores · 36 GB · macOS', await summaryOf(b, 'This machine'))
  check('Software says what the helper is', /^helper /.test(await summaryOf(b, 'Software')), await summaryOf(b, 'Software'))
  check('Ruvio says off', (await summaryOf(b, 'Ruvio')) === 'off')
  check('Limits says none are set', (await summaryOf(b, 'Limits')) === 'no limits set', await summaryOf(b, 'Limits'))
  check('A new VM gets says it uses the standard sizes', (await summaryOf(b, 'A new VM gets')) === 'uses the standard sizes')
  check('Names says the name', (await summaryOf(b, 'Names')) === 'mac-studio', await summaryOf(b, 'Names'))
  check('the read-only rows have no changed dot', rows.slice(0, 3).every((row) => !row.changed))
  const last = rows[rows.length - 1]
  check('with all rows closed the six headers fit above the fold at 1280x800', (last?.headerBottom ?? Infinity) < LAPTOP.height, `last header bottom ${last?.headerBottom}`)
  check('the tab is one column of rows, at most about 820px wide, from the tab bar edge', await b.run(() => {
    const env = document.querySelector('.env')?.getBoundingClientRect()
    const tabs = document.querySelector('[role=tablist]')?.getBoundingClientRect()
    return !!env && !!tabs && env.width <= 821 && Math.abs(env.left - (tabs.left + 28)) <= 1
  }))
  await b.shot('env-collapsed-desktop.png')
}

/** Pressing a header opens that row only; Enter and Space on a focused header toggle it; Expand all and Collapse all work. */
export async function opening(page: Page, b: Browse): Promise<void> {
  await pressHeader(b, 'Limits')
  check('pressing a header opens that row only', (await openTitles(b)) === 'Limits', await openTitles(b))
  check('the opened row shows its fields', await b.run(() => document.querySelector<HTMLElement>('#env-ramReserveMb')?.offsetParent !== null))
  await pressHeader(b, 'Software')
  check('rows open independently of each other', (await openTitles(b)) === 'Software|Limits', await openTitles(b))
  await pressHeader(b, 'Software')
  await pressHeader(b, 'Limits')
  await page.focus(`${ROW}[aria-label="Names"] button.trigger`)
  await page.keyboard.press('Enter')
  check('Enter opens a focused row and aria-expanded follows', (await rowNamed(b, 'Names')).expanded)
  await page.keyboard.press('Space')
  check('Space closes it again and aria-expanded follows', !(await rowNamed(b, 'Names')).expanded)
  const ring = await b.run(() => { const style = getComputedStyle(document.activeElement ?? document.body); return `${style.outlineStyle} ${style.outlineWidth}` })
  check('a focused header shows a focus ring', /^solid [1-9]/.test(ring), ring)
  check('the link above the rows says Expand all', (await expandAllLabel(b)) === 'Expand all')
  await pressExpandAll(b)
  check('Expand all opens every row', (await openTitles(b)) === ROW_TITLES, await openTitles(b))
  check('the link now says Collapse all', (await expandAllLabel(b)) === 'Collapse all')
  await pressExpandAll(b)
  check('Collapse all closes every row', (await openTitles(b)) === '', await openTitles(b))
}

/** An edit changes its row's summary and shows its dot while the row is closed; closing and opening again keeps the edit. */
export async function editsInClosedRows(b: Browse): Promise<void> {
  await openRow(b, 'A new VM gets')
  await changeField(b, 'vmCpu', '7')
  await pressHeader(b, 'A new VM gets')
  const row = await rowNamed(b, 'A new VM gets')
  check('a closed row shows the current, unsaved values in its summary', row.summary === '7 CPU', row.summary)
  check('a closed row with unsaved edits shows the changed dot, and the others do not', row.changed && (await rowStates(b)).filter((state) => state.changed).length === 1)
  check('the fields of a closed row are not shown', await b.run(() => document.querySelector<HTMLElement>('#env-vmCpu')?.offsetParent === null))
  await openRow(b, 'A new VM gets')
  check('opening the row again keeps what was typed', (await fieldValue(b, 'vmCpu')) === '7')
  await b.until((selector) => !!document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  check('the bar says one section changed', /Unsaved changes in 1 section\b(?!s)/.test(await barText(b)), await barText(b))
  await openRow(b, 'Names')
  await changeField(b, 'labels', 'lab, gpu')
  check('the Names summary counts the labels', (await summaryOf(b, 'Names')) === 'mac-studio · 2 labels', await summaryOf(b, 'Names'))
  await b.until((selector) => /Unsaved changes in 2 sections/.test(document.querySelector<HTMLElement>(selector)?.innerText ?? ''), { timeout: SHORT_WAIT_MS }, BAR)
  check('the bar says two sections changed', /Unsaved changes in 2 sections/.test(await barText(b)), await barText(b))
  await b.shot('env-two-open-desktop.png')
  await b.click('Undo')
  await b.until((selector) => !document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  const after = await rowStates(b)
  check('Undo puts every value back and removes the dots', (await fieldValue(b, 'vmCpu')) === '' && (await fieldValue(b, 'labels')) === '' && after.every((state) => !state.changed))
  check('Undo puts the summaries back', (await summaryOf(b, 'A new VM gets')) === 'uses the standard sizes' && (await summaryOf(b, 'Names')) === 'mac-studio')
}

/** Types into a field the way another part of the page could while its row is closed: the value changes without the person opening the row. */
const setHiddenField = (b: Browse, name: string, value: string) => b.run((id, text) => {
  const input = document.querySelector<HTMLInputElement>(`#env-${id}`)
  if (!input) throw new Error(`no field ${id}`)
  input.value = text
  input.dispatchEvent(new Event('input', { bubbles: true }))
}, name, value)

/** A row with an error opens by itself, shows the error badge, refuses to close while the error stands, and Save waits. */
export async function errorOpensRow(b: Browse): Promise<void> {
  for (const row of await rowStates(b)) if (row.expanded) await pressHeader(b, row.title)
  check('the row is closed before the error', !(await rowNamed(b, 'A new VM gets')).expanded)
  await setHiddenField(b, 'vmCpu', INVALID_CPU)
  await b.until((rowSelector) => document.querySelector(`${rowSelector}[aria-label="A new VM gets"] button.trigger`)?.getAttribute('aria-expanded') === 'true', { timeout: SHORT_WAIT_MS }, ROW)
  const row = await rowNamed(b, 'A new VM gets')
  check('an invalid value opens its row by itself and shows the error badge', row.expanded && row.error && !row.bodyHidden)
  check('the other rows stay closed and have no badge', (await rowStates(b)).filter((state) => state.error || state.expanded).length === 1)
  await pressHeader(b, 'A new VM gets')
  check('the row stays open while the error exists', (await rowNamed(b, 'A new VM gets')).expanded)
  check('Save waits while a value is refused', await b.isDisabled('Save'))
  await b.shot('env-error-bar-desktop.png')
  await changeField(b, 'vmCpu', '4')
  const fixed = await rowNamed(b, 'A new VM gets')
  check('fixing the value removes the badge, and the row stays open under the person\'s hands', !fixed.error && fixed.expanded)
  await b.click('Undo')
  await b.until((selector) => !document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  await pressHeader(b, 'A new VM gets')
}

/** Nothing changed: no bar. A change: the bar. Undo: the old value and no bar. */
export async function barFollowsChanges(b: Browse): Promise<void> {
  check('the save bar is hidden while nothing changed', !(await barShown(b)))
  const before = await fieldValue(b, 'vmCpu')
  await changeField(b, 'vmCpu', '7')
  await b.until((selector) => !!document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  const text = await barText(b)
  check('typing shows the bar with Unsaved changes, Save, Undo and the apply-to-new-VMs note', /Unsaved changes in 1 section/.test(text) && /Save/.test(text) && /Undo/.test(text) && text.includes('Changes apply to new VMs only.'), text)
  const sticky = await b.run((selector) => {
    const bar = document.querySelector<HTMLElement>(selector)
    const box = bar?.getBoundingClientRect()
    return bar && box ? { position: getComputedStyle(bar).position, bottom: Math.round(window.innerHeight - box.bottom) } : null
  }, BAR)
  check('the bar is sticky and sits at the bottom edge of the screen', sticky?.position === 'sticky' && sticky.bottom <= SAME_PIXEL, JSON.stringify(sticky))
  await b.click('Undo')
  await b.until((selector) => !document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  check('Undo restores the saved value and hides the bar', (await fieldValue(b, 'vmCpu')) === before && !(await barShown(b)))
  check('Save is not in the page while nothing changed', !(await b.run(() => [...document.querySelectorAll('button')].some((button) => button.textContent?.trim() === 'Save'))))
}

/** Five quick presses on Save send one request, show Saved for a moment, then the bar goes away. */
export async function rapidSave(b: Browse, patches: unknown[]): Promise<void> {
  const sent = patches.length
  await b.run((selector, times) => {
    const save = [...document.querySelectorAll<HTMLButtonElement>(`${selector} button`)].find((button) => button.textContent?.trim() === 'Save')
    for (let press = 0; press < times; press++) save?.click()
  }, BAR, RAPID_CLICKS)
  await b.until((selector) => /Saved/.test(document.querySelector<HTMLElement>(selector)?.innerText ?? ''), { timeout: SHORT_WAIT_MS }, BAR)
  check('five quick presses on Save send one request', patches.length === sent + 1, `${patches.length - sent} requests`)
  await b.until((selector) => !document.querySelector(selector), { timeout: SAVED_LINE_MS + SHORT_WAIT_MS }, BAR)
  check('after Save the bar is gone', !(await barShown(b)))
}

/** On a phone: the same rows, summaries wrap to at most two lines, no sideways scroll, with the bar and without. */
export async function phoneRows(page: Page, b: Browse): Promise<void> {
  await page.setViewport(PHONE)
  await changeField(b, 'vmCpu', '5')
  await b.until((selector) => !!document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  await expectNoSideScroll(b, 'Environment with every row open and the save bar, 400px')
  await pressExpandAll(b)
  const rows = await rowStates(b)
  check('Collapse all closes the rows on a phone too', rows.every((row) => !row.expanded))
  check('on a phone there are the same six rows in order', rows.map((row) => row.title).join('|') === ROW_TITLES)
  check('on a phone every summary fits in at most two lines', rows.every((row) => row.summaryHeight > 0 && row.summaryHeight <= TWO_LINES_MAX_PX), JSON.stringify(rows.map((row) => row.summaryHeight)))
  await expectNoSideScroll(b, 'Environment, all rows closed, 400px')
  await b.shot('env-collapsed-phone.png')
}
