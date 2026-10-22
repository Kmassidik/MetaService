// The VM list actions as icon buttons: every one has a name, the tooltip shows on hover and on keyboard focus, Delete is last, apart and red, the hit area is big enough,
// and nothing makes the page scroll sideways on a phone. (Five rapid Start clicks sending one request is proved in guard.ts, which now presses these same icons.)
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { fresh, openTable } from './guard.ts'
import type { StandIn } from './standin.ts'

const MACHINE_TABLE = '#/machines/details?id=studio&tab=vms'
const ALL_VMS = '#/vms'
const MIN_HIT_PX = 36
const MIN_GAP_PX = 12
const PHONE = { width: 400, height: 844 }
const DESKTOP = { width: 1280, height: 800 }
const SHORT_WAIT_MS = 8000
/** vm1 of the stand-in is running and has no chat: Terminal (off: the stand-in is not a Mac), Stop, Install chat, then Delete. */
const VM1_ROW_LABELS = ['Terminal: Mac machines only for now vm1', 'SSH keys vm1', 'Stop vm1', 'Install chat vm1', 'Delete vm1']
/** What the tooltip of each of those says: the short word, without the VM's name. */
const VM1_ROW_TIPS = ['Terminal: Mac machines only for now', 'SSH keys', 'Stop', 'Install chat', 'Delete']
const ROW_BUTTONS = '.vm-acts button'

interface Geometry {
  labels: string[]
  tips: string[]
  smallest: number
  gapBeforeDelete: number
  deleteIsLast: boolean
  deleteColour: string
  stopColour: string
}

const rowGeometry = (b: Browse, rowIndex: number): Promise<Geometry> =>
  b.run((selector, index) => {
    const row = document.querySelectorAll('tbody tr')[index]
    const buttons = [...(row?.querySelectorAll<HTMLButtonElement>(selector) ?? [])]
    const rects = buttons.map((button) => button.getBoundingClientRect())
    const last = buttons[buttons.length - 1]
    const before = rects[rects.length - 2]
    const lastRect = rects[rects.length - 1]
    const stop = buttons.find((button) => button.getAttribute('aria-label') === 'Stop')
    return {
      labels: buttons.map((button) => button.getAttribute('aria-label') ?? ''),
      tips: buttons.map((button) => button.getAttribute('data-tip') ?? ''),
      smallest: Math.min(...rects.map((rect) => Math.min(rect.width, rect.height))),
      gapBeforeDelete: before && lastRect ? lastRect.left - before.right : 0,
      deleteIsLast: last?.getAttribute('data-tip') === 'Delete',
      deleteColour: last ? getComputedStyle(last).color : '',
      stopColour: stop ? getComputedStyle(stop).color : '',
    }
  }, ROW_BUTTONS, rowIndex)

const channels = (colour: string): number[] => (colour.match(/\d+(\.\d+)?/g) ?? []).map(Number)

const isRed = (colour: string): boolean => {
  const [red = 0, green = 0, blue = 0] = channels(colour)
  return red > 120 && red > green * 2 && red > blue * 2
}

/** The tooltip of one button: what its ::after says and whether it is showing. */
const tooltipOf = (b: Browse, label: string) =>
  b.run((wanted) => {
    const button = [...document.querySelectorAll<HTMLButtonElement>('.vm-acts button')].find((entry) => entry.getAttribute('aria-label') === wanted)
    if (!button) return { found: false, words: '', shown: false }
    const after = getComputedStyle(button, '::after')
    return { found: true, words: after.content.replace(/^"|"$/g, ''), shown: after.opacity === '1' }
  }, label)

async function everyButtonHasAName(b: Browse, where: string): Promise<void> {
  const nameless = await b.run(() => [...document.querySelectorAll<HTMLButtonElement>('tbody button')].filter((button) => (button.getAttribute('aria-label') ?? '') === '').length)
  const count = await b.run(() => document.querySelectorAll('tbody button').length)
  check(`${where}: every icon button has an aria-label (${count} buttons)`, count > 0 && nameless === 0, `${nameless} without`)
}

async function orderAndLook(b: Browse): Promise<void> {
  const geometry = await rowGeometry(b, 0)
  check('machine page table: a running VM without a chat shows Terminal, SSH keys, Stop, Install chat, then Delete', JSON.stringify(geometry.labels) === JSON.stringify(VM1_ROW_LABELS), JSON.stringify(geometry.labels))
  check('machine page table: the tooltip words are the short names, the spoken names add the VM', JSON.stringify(geometry.tips) === JSON.stringify(VM1_ROW_TIPS))
  check(`machine page table: Delete is last, set apart by a gap of at least ${MIN_GAP_PX}px, and red`, geometry.deleteIsLast && geometry.gapBeforeDelete >= MIN_GAP_PX && isRed(geometry.deleteColour) && !isRed(geometry.stopColour), JSON.stringify(geometry))
  check(`machine page table: every button is at least ${MIN_HIT_PX}px`, geometry.smallest >= MIN_HIT_PX, `${geometry.smallest}`)
}

async function tooltipsOnHoverAndFocus(b: Browse): Promise<void> {
  check('the tooltip is hidden while nothing points at the button', !(await tooltipOf(b, 'Stop vm1')).shown)
  const button = await b.page.$('button[aria-label="Stop vm1"]')
  if (!button) throw new Error('there is no Stop button')
  await button.hover()
  await b.until(() => getComputedStyle(document.querySelector('.vm-acts button[aria-label="Stop vm1"]') as Element, '::after').opacity === '1', { timeout: SHORT_WAIT_MS })
  const hovered = await tooltipOf(b, 'Stop vm1')
  check('hovering a button shows its label as a tooltip', hovered.found && hovered.shown && hovered.words === 'Stop', JSON.stringify(hovered))
  await b.shot('icons-tooltip-hover.png')
  await b.page.mouse.move(2, 2)
  await b.until(() => getComputedStyle(document.querySelector('.vm-acts button[aria-label="Stop vm1"]') as Element, '::after').opacity === '0', { timeout: SHORT_WAIT_MS })
  await b.page.keyboard.press('Shift')
  await b.run(() => document.querySelector<HTMLButtonElement>('.vm-acts button[aria-label="Delete vm1"]')?.focus())
  await b.until(() => getComputedStyle(document.querySelector('.vm-acts button[aria-label="Delete vm1"]') as Element, '::after').opacity === '1', { timeout: SHORT_WAIT_MS })
  const focused = await tooltipOf(b, 'Delete vm1')
  check('keyboard focus on a button shows its label as a tooltip', focused.shown && focused.words === 'Delete', JSON.stringify(focused))
  await b.shot('icons-tooltip-focus.png')
  await b.run(() => document.querySelector<HTMLElement>('.vm-acts button[aria-label="Delete vm1"]')?.blur())
}

const noSideScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

async function onAPhone(b: Browse, standin: StandIn): Promise<void> {
  await b.page.setViewport(PHONE)
  await fresh(b, standin, MACHINE_TABLE)
  await openTable(b)
  check('phone: the machine page table does not scroll sideways', await noSideScroll(b))
  const words = await b.run(() => [...document.querySelectorAll<HTMLElement>('tbody tr:first-child .vm-acts button')].map((button) => button.innerText.trim()))
  check('phone: the buttons keep a short word beside the icon', words.includes('Stop') && words.includes('Install') && words.includes('Delete'), JSON.stringify(words))
  await b.shot('icons-machine-table-phone.png', true)
  await fresh(b, standin, ALL_VMS)
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  check('phone: All VMs does not scroll sideways', await noSideScroll(b))
  await b.shot('icons-all-vms-phone.png', true)
  await b.page.setViewport(DESKTOP)
}

async function onAllVms(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, ALL_VMS)
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr')
  await everyButtonHasAName(b, 'All VMs')
  const labels = await b.run(() => [...document.querySelectorAll('tbody tr')].map((row) => [...row.querySelectorAll('.vm-acts button')].map((button) => button.getAttribute('aria-label') ?? '').join('|')))
  const lastIsDelete = labels.every((row) => /\|Delete vm\d+$/.test(row))
  check('All VMs: every row has Delete as its last button', lastIsDelete, JSON.stringify(labels))
  const idUnderName = await b.run(() => document.querySelector('tbody tr .vm-id')?.textContent?.trim() ?? '')
  check('All VMs: the ID is under the name', idUnderName !== '', idUnderName)
  await b.shot('icons-all-vms.png')
}

export async function iconButtonsLookAndWork(b: Browse, standin: StandIn): Promise<void> {
  await fresh(b, standin, MACHINE_TABLE)
  await openTable(b)
  await everyButtonHasAName(b, 'machine page table')
  await orderAndLook(b)
  const copy = await b.run(() => document.querySelector('tbody tr .addr button')?.getAttribute('aria-label'))
  check('machine page table: the address has a copy icon with its label', copy === 'Copy address vm1', `${copy}`)
  const idColumn = await b.run(() => [...document.querySelectorAll('thead th')].some((cell) => cell.textContent?.trim() === 'ID'))
  check('machine page table: there is no ID column any more', !idColumn)
  await tooltipsOnHoverAndFocus(b)
  await b.shot('icons-machine-table.png')
  await onAllVms(b, standin)
  await onAPhone(b, standin)
}
