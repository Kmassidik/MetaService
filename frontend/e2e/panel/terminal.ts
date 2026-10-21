// The web terminal of a VM in a real browser: open it from the VM page, type into the real shell, see the screen size follow the window,
// close it with Escape and with Close, and Reconnect after the shell ends (which must ask for a new ticket).
import { check } from '../support/check.ts'
import { wait } from '../support/net.ts'
import type { Browse } from '../support/page.ts'
import { openTab, pickView } from './machines.ts'
import { terminalButtonsScenario } from './terminal-buttons.ts'
import { createAVm } from './workloads.ts'
import { startAgent, type World } from './world.ts'

const VM = 'term-box'
const MACHINE = 'agent-mac'
const SHORT_WAIT_MS = 10000
const AGENT_WAIT_MS = 20000
const OUTPUT_WAIT_MS = 15000
/** The parent lets a console go a moment after Close; the next one is opened after this pause. */
const CLOSE_SETTLE_MS = 1500
const DEFAULT_COLS = 80
const BUTTON = '▸ Web terminal'

/** Everything the page asked the Root for as a console ticket. */
export interface TicketLog {
  count: number
}

export const watchTickets = (b: Browse): TicketLog => {
  const log: TicketLog = { count: 0 }
  b.page.on('request', (request) => request.method() === 'POST' && /\/workloads\/[^/]+\/terminal$/.test(request.url()) && log.count++)
  return log
}

/** The terminal's rows, one per line, with the padding xterm adds to every row (non-breaking spaces) taken off. */
const READ_ROWS = () => [...document.querySelectorAll<HTMLElement>('.xterm-rows > div')].map((row) => (row.textContent ?? '').replace(/\u00a0/g, ' ').replace(/\s+$/, '')).join('\n')
const screen = (b: Browse) => b.run(READ_ROWS)
const statusLine = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('.tstatus')?.innerText ?? '')
export const isOpen = (b: Browse) => b.run(() => document.querySelector('.term-box') !== null)
export const untilConnected = (b: Browse) => b.until(() => /connected/i.test(document.querySelector<HTMLElement>('.tstatus')?.innerText ?? '') && !/disconnected/i.test(document.querySelector<HTMLElement>('.tstatus')?.innerText ?? ''), { timeout: SHORT_WAIT_MS })

export async function typeLine(b: Browse, line: string): Promise<void> {
  await b.page.focus('.xterm-helper-textarea')
  await b.page.keyboard.type(line)
  await b.page.keyboard.press('Enter')
}

export async function untilScreenHas(b: Browse, pattern: RegExp): Promise<string> {
  try {
    await b.until((source) => new RegExp(source, 'm').test([...document.querySelectorAll<HTMLElement>('.xterm-rows > div')].map((row) => (row.textContent ?? '').replace(/\u00a0/g, ' ').replace(/\s+$/, '')).join('\n')), { timeout: OUTPUT_WAIT_MS }, pattern.source)
  } catch {
    await b.shot('terminal-stuck.png')
    const seen = await b.run(() => ({ rows: document.querySelector<HTMLElement>('.xterm-rows')?.innerText ?? 'no .xterm-rows', parts: [...document.querySelectorAll('.term *')].slice(0, 12).map((node) => node.className).join(' | '), status: document.querySelector<HTMLElement>('.tstatus')?.innerText ?? '' }))
    throw new Error(`waiting for ${pattern} failed; status "${seen.status}"; screen "${seen.rows.replace(/\s+/g, ' ').slice(0, 300)}"; term parts: ${seen.parts}`)
  }
  return screen(b)
}

async function goToTheVmPage(b: Browse): Promise<void> {
  await b.go('#/machines')
  await b.until((name) => document.body.innerText.includes(name), { timeout: AGENT_WAIT_MS }, MACHINE)
  await b.go(`#/machines/details?id=${MACHINE}`)
  await b.until((name) => document.querySelector('.phead h1')?.textContent === name, { timeout: SHORT_WAIT_MS }, MACHINE)
  await createAVm(b, VM)
  await openTab(b, 'VMs')
  await pickView(b, 'Table')
  await b.page.waitForSelector('td.c-name a')
  await b.run((name) => [...document.querySelectorAll<HTMLAnchorElement>('td.c-name a')].find((link) => link.textContent?.trim() === name)?.click(), VM)
  await b.until(() => [...document.querySelectorAll('.phead button')].some((button) => button.textContent?.trim() === '▸ Web terminal'), { timeout: AGENT_WAIT_MS })
}

async function opensAndWorks(b: Browse, tickets: TicketLog): Promise<void> {
  await b.click(BUTTON)
  await b.page.waitForSelector('.term-box .xterm')
  check('the Web terminal opens in a window titled "Terminal · <vm>"', (await b.run(() => document.querySelector<HTMLElement>('.ttitle')?.innerText ?? '')).startsWith('Terminal · '))
  await untilConnected(b)
  check('the status turns to connected, with one ticket asked for', tickets.count === 1, String(tickets.count))
  await typeLine(b, 'echo hello-$((40+2))')
  check('what is typed reaches the shell on the VM and its answer is shown', /^hello-42$/m.test(await untilScreenHas(b, /^hello-42$/m)))
  await typeLine(b, 'echo size-$(stty size | tr " " x)')
  const size = /size-(\d+)x(\d+)/.exec(await untilScreenHas(b, /size-\d+x\d+/))
  check('the screen size follows the window: wider than the 80 columns the shell starts with', Number(size?.[2]) > DEFAULT_COLS, size?.[0] ?? 'no size line')
  await b.shot('terminal-open.png')
}

async function closesWithEscape(b: Browse): Promise<void> {
  await b.page.focus('.xterm-helper-textarea')
  await b.page.keyboard.press('Escape')
  await wait(CLOSE_SETTLE_MS)
  check('Escape typed inside the terminal goes to the shell and does not close the window (vim needs it)', await isOpen(b))
  await b.page.focus('.modal')
  await b.page.keyboard.press('Escape')
  await b.until(() => document.querySelector('.term-box') === null, { timeout: SHORT_WAIT_MS })
  check('Escape closes the window when the focus is on the window itself', !(await isOpen(b)))
  await wait(CLOSE_SETTLE_MS)
}

async function reconnectsWithANewTicket(b: Browse, tickets: TicketLog): Promise<void> {
  await b.click(BUTTON)
  await b.page.waitForSelector('.term-box .xterm')
  await untilConnected(b)
  const before = tickets.count
  await typeLine(b, 'exit')
  await b.until(() => /disconnected/i.test(document.querySelector<HTMLElement>('.tstatus')?.innerText ?? ''), { timeout: OUTPUT_WAIT_MS })
  check('when the shell ends the status says disconnected and why', /disconnected · the shell ended/i.test(await statusLine(b)), await statusLine(b))
  check('Reconnect is offered once the socket is gone', (await b.text()).includes('Reconnect'))
  await b.shot('terminal-disconnected.png')
  await b.click('Reconnect')
  await untilConnected(b)
  check('Reconnect asks for a NEW ticket', tickets.count === before + 1, `${before} then ${tickets.count}`)
  await typeLine(b, 'echo dup-$((1+1))')
  const shown = await untilScreenHas(b, /^dup-2$/m)
  check('after a Reconnect each keystroke is still sent once (the command ran once)', (shown.match(/^dup-2$/gm) ?? []).length === 1)
}

async function closesWithTheButton(b: Browse): Promise<void> {
  await b.click('✕ Close')
  await b.until(() => document.querySelector('.term-box') === null, { timeout: SHORT_WAIT_MS })
  check('Close closes the window', !(await isOpen(b)))
  await wait(CLOSE_SETTLE_MS)
  await b.click(BUTTON)
  await untilConnected(b)
  check('closing released the VM\'s console: it can be opened again', true)
  await b.click('✕ Close')
}

export async function terminalScenario(b: Browse, world: World): Promise<void> {
  const tickets = watchTickets(b)
  const agent = await startAgent(world)
  try {
    await goToTheVmPage(b)
    await opensAndWorks(b, tickets)
    await closesWithEscape(b)
    await reconnectsWithANewTicket(b, tickets)
    await closesWithTheButton(b)
    await terminalButtonsScenario(b, world)
  } finally {
    agent.kill()
  }
}
