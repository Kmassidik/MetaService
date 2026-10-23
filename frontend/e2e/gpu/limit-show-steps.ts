// Where a GPU memory limit shows in a real browser: the booking line and bar on the Live tab, the "GPU 4 GB" chip in the three VM lists, the VM page row, and why a VM stopped when it ran over its limit.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { BOOKED_GB, HOSTILE_MESSAGE, LIMITED_VM, OLD_PC, SHARE_PC, STOPPED_VM, TOTAL_GB, WHOLE_CARD_VM } from './limit-stand-in.ts'

const SHORT_WAIT_MS = 10000
const CHIP = '[data-gpu-limit-chip]'
const CHIP_TEXT = 'GPU 4 GB'
const CHIP_TITLE = 'GPU memory limit, booked for this VM'
const HINT = 'Its GPU memory limit is still booked. Start it again, or delete it to free the booking.'
const MESSAGE_START = 'It used 6 GB of GPU memory; its limit is 4 GB.'

const machineUrl = (base: string, id: string, rest = '') => `${base}/#/machines/details?id=${id}${rest}`

export async function bookingOnTheLiveTab(b: Browse, base: string, booked = BOOKED_GB): Promise<void> {
  await b.page.goto(machineUrl(base, SHARE_PC), { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('[data-testid=gpu-booking]', { timeout: SHORT_WAIT_MS })
  const card = await b.run(() => ({ text: document.querySelector<HTMLElement>('[data-testid=gpu-booking]')?.innerText.trim() ?? '', bar: document.querySelector('[data-testid=gpu-booking] .bar i')?.getAttribute('style') ?? '' }))
  check(`the GPU card says "Booked for VMs: ${booked} of ${TOTAL_GB} GB · free ${TOTAL_GB - booked} GB" with a bar`, card.text === `Booked for VMs: ${booked} of ${TOTAL_GB} GB · free ${TOTAL_GB - booked} GB` && card.bar.includes('width'), JSON.stringify(card))
  await b.shot('gpu-limit-live-booking.png')
  await b.page.goto(machineUrl(base, OLD_PC), { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('[data-testid=gpu-0]', { timeout: SHORT_WAIT_MS })
  check('a machine without a booking has no booking line', await b.run(() => document.querySelector('[data-testid=gpu-booking]') === null))
}

const chipsIn = (b: Browse, rows: string) =>
  b.run((where, chip) => [...document.querySelectorAll<HTMLElement>(where)].map((row) => ({ name: row.innerText.trim().split(/\s+/)[0] ?? '', chip: row.querySelector<HTMLElement>(chip)?.innerText.trim() ?? null, title: row.querySelector<HTMLElement>(chip)?.title ?? null })), rows, CHIP)

function chipsAreRight(rows: { name: string; chip: string | null; title: string | null }[]): boolean {
  const byName = (name: string) => rows.find((row) => row.name === name)
  const limited = [LIMITED_VM, STOPPED_VM].every((name) => byName(name)?.chip === CHIP_TEXT && byName(name)?.title === CHIP_TITLE)
  return limited && byName(WHOLE_CARD_VM)?.chip === null
}

export async function chipsInTheLists(b: Browse, base: string): Promise<void> {
  await b.page.goto(`${base}/#/vms`, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('table[aria-label="VMs"] tbody tr', { timeout: SHORT_WAIT_MS })
  const all = await chipsIn(b, 'table[aria-label="VMs"] tbody tr')
  check('All VMs: the two limited VMs carry "GPU 4 GB" with the hover text, the whole-card one does not', chipsAreRight(all), JSON.stringify(all))
  await b.shot('gpu-limit-all-vms.png')
  await b.page.goto(machineUrl(base, SHARE_PC, '&tab=vms'), { waitUntil: 'networkidle0' })
  await b.click('Table')
  await b.page.waitForSelector('.restable tbody tr', { timeout: SHORT_WAIT_MS })
  const table = await chipsIn(b, '.restable tbody tr')
  check('machine page Table view: the same chips', chipsAreRight(table), JSON.stringify(table))
  await b.click('Cards')
  await b.page.waitForSelector('.grid .card', { timeout: SHORT_WAIT_MS })
  const cards = await chipsIn(b, '.grid .card')
  check('machine page Cards view: the same chips', chipsAreRight(cards), JSON.stringify(cards))
}

export async function vmPageRow(b: Browse, base: string): Promise<void> {
  const rowOf = async (vm: string) => {
    await b.page.goto(machineUrl(base, SHARE_PC, `&vm=${vm}`), { waitUntil: 'networkidle0' })
    await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, vm)
    return b.run(() => [...document.querySelectorAll<HTMLElement>('dl.kv > div')].map((row) => row.innerText.replace(/\s+/g, ' ').trim()))
  }
  const limited = await rowOf(LIMITED_VM)
  check('the VM page Overview has a "GPU memory limit" row reading "4 GB (booked)"', limited.some((row) => row.toLowerCase() === 'gpu memory limit 4 gb (booked)'), JSON.stringify(limited))
  const whole = await rowOf(WHOLE_CARD_VM)
  check('a VM without a limit has no such row', !whole.some((row) => row.toLowerCase().includes('gpu memory limit')))
}

export async function overLimitReason(b: Browse, base: string): Promise<void> {
  await b.page.goto(machineUrl(base, SHARE_PC, `&vm=${STOPPED_VM}`), { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('section.why', { timeout: SHORT_WAIT_MS })
  const why = await b.run(() => ({ text: document.querySelector<HTMLElement>('section.why')?.innerText ?? '', markup: document.querySelector('section.why img, section.why script') !== null, flag: window.__limitxss, codebox: document.querySelector('section.why .codebox') !== null }))
  check('"Why it stopped" shows the reason message as plain text and the hint about the booking', why.text.includes(HOSTILE_MESSAGE) && why.text.includes(MESSAGE_START) && why.text.includes(HINT), why.text)
  check('a hostile message stays text: no tag appears, nothing runs', !why.markup && why.flag === undefined)
  check('no exit code and no log box for this reason', !why.text.includes('exit code') && !why.text.includes('Exit code') && !why.codebox, why.text)
  await b.shot('gpu-limit-stopped-vm.png')
  await b.page.goto(machineUrl(base, SHARE_PC, '&tab=vms'), { waitUntil: 'networkidle0' })
  await b.click('Table')
  await b.page.waitForSelector('.restable tbody tr', { timeout: SHORT_WAIT_MS })
  await b.page.click('.restable details.why summary')
  check('the compact "Why it stopped" in the list shows the message too', (await b.run(() => document.querySelector<HTMLElement>('.restable details.why')?.innerText ?? '')).includes(MESSAGE_START))
}
