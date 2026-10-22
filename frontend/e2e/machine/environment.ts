// The Environment tab's two columns and its save bar, as a person sees them.
import type { Page } from 'puppeteer-core'
import { SHORT_WAIT_MS, changeField, expectNoSideScroll, fieldValue } from './steps.ts'
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'

const BAR = '[aria-label="Save bar"]'
const SAVED_LINE_MS = 2000
const SAME_PIXEL = 1
const PAGE_PADDING = 28
const RAPID_CLICKS = 5
const PHONE = { width: 400, height: 844 }
const LAPTOP = { width: 1280, height: 800 }
const LEFT_SECTIONS = 'This machine|Software'
const RIGHT_SECTIONS = 'Ruvio|Limits|A new VM gets|Names'

export const barShown = (b: Browse) => b.run((selector) => !!document.querySelector(selector), BAR)

const sectionsOf = (b: Browse, column: 'left' | 'right') => b.run((which) => {
  const root = document.querySelector(which === 'left' ? '.env > .col:first-child' : '.env > .col:nth-child(2)')
  return [...(root?.querySelectorAll('section[aria-label]') ?? [])].map((section) => section.getAttribute('aria-label')).join('|')
}, column)

const columnEdges = (b: Browse) => b.run(() => {
  const box = (selector: string) => document.querySelector(selector)?.getBoundingClientRect()
  const left = box('.env > .col:first-child')
  const right = box('.env > .col:nth-child(2)')
  const tabs = box('[role=tablist]')
  const first = (selector: string) => box(selector)?.top ?? -1
  return {
    leftTop: first('.env > .col:first-child > :first-child'), rightTop: first('.env > .col:nth-child(2) > :first-child'),
    leftLeft: left?.left ?? -1, rightLeft: right?.left ?? -1, rightRight: right?.right ?? -1, gap: (right?.left ?? 0) - (left?.right ?? 0),
    tabsLeft: tabs?.left ?? -1, tabsRight: tabs?.right ?? -1, width: window.innerWidth,
  }
})

/** At laptop width: the facts on the left, the form on the right, same top, and the page edges of the tab bar. */
export async function twoColumns(page: Page, b: Browse): Promise<void> {
  await page.setViewport(LAPTOP)
  check('left column has This machine, Software', (await sectionsOf(b, 'left')) === LEFT_SECTIONS, await sectionsOf(b, 'left'))
  check('right column has Ruvio, Limits, A new VM gets, Names', (await sectionsOf(b, 'right')) === RIGHT_SECTIONS, await sectionsOf(b, 'right'))
  const edges = await columnEdges(b)
  const aligned = (one: number, other: number) => Math.abs(one - other) <= SAME_PIXEL
  check('both columns start at the same top and a gap apart', aligned(edges.leftTop, edges.rightTop) && edges.gap >= 16, JSON.stringify(edges))
  check('the columns run from the left edge of the tab bar to its right edge', aligned(edges.leftLeft, edges.tabsLeft + PAGE_PADDING) && aligned(edges.rightRight, edges.tabsRight - PAGE_PADDING), JSON.stringify(edges))
}

/** Nothing changed: no bar. A change: the bar. Undo: the old value and no bar. */
export async function barFollowsChanges(b: Browse): Promise<void> {
  check('the save bar is hidden while nothing changed', !(await barShown(b)))
  const before = await fieldValue(b, 'vmCpu')
  await changeField(b, 'vmCpu', '7')
  await b.until((selector) => !!document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  const text = await b.run((selector) => document.querySelector<HTMLElement>(selector)?.innerText ?? '', BAR)
  check('typing shows the bar with Unsaved changes, Save, Undo and the apply-to-new-VMs note', /Unsaved changes/.test(text) && /Save/.test(text) && /Undo/.test(text) && text.includes('Changes apply to new VMs only.'), text)
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

/** On a phone: one column, no sideways scroll, the bar fits. */
export async function phoneOneColumn(page: Page, b: Browse): Promise<void> {
  await page.setViewport(PHONE)
  await changeField(b, 'vmCpu', '5')
  await b.until((selector) => !!document.querySelector(selector), { timeout: SHORT_WAIT_MS }, BAR)
  const edges = await columnEdges(b)
  check('on a phone the form sits under the facts in one column', edges.rightTop > edges.leftTop && edges.leftLeft === edges.rightLeft, JSON.stringify(edges))
  await expectNoSideScroll(b, 'Environment with the save bar, 400px')
}
