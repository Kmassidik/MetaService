// How each page of the theme pictures is reached. Every step leaves the page open, ready to be photographed.
import type { HTTPRequest } from 'puppeteer-core'
import type { Requirement } from '../../src/lib/types.ts'
import { ADMIN } from '../support/admin.ts'
import type { Browse } from '../support/page.ts'
import { SCAN_PREFIX } from '../support/root.ts'
import { openMachine, openTab } from '../machine/steps.ts'
import { MAC, OFFLINE } from './fleet.ts'

const SHORT_WAIT_MS = 10000
const STEP_WAIT_MS = 20000
const FOUND_ADDRESS = `${SCAN_PREFIX}.40`
const LOOPBACK = '127.0.0.1'
const LIVE_MACHINE = 'studio'

const PASSING = (id: string, label: string): Requirement => ({ id, label, ok: true, detail: 'Found.' })
const MISSING_INCUS: Requirement = { id: 'vm_tool', label: 'Incus (makes the VMs)', ok: false, detail: 'Not installed.', fix: 'Install Incus on that computer: sudo apt install incus' }
const MISSING_PYTHON: Requirement = { id: 'python', label: 'Python (runs the chat)', ok: false, detail: 'Not installed.', fix: 'Install it with sudo apt install python3, then check again.' }
const LINUX_FACTS = { os: 'Linux', arch: 'x86_64', version: 'Ubuntu 24.04', chip: 'AMD Ryzen 9 5950X', user: 'luca', home: '/home/luca', cpu_cores: 32, ram_mb: 64000, disk_free_gb: 79 }

/** The sign-in page, before anyone is signed in. */
export async function loginPage(b: Browse, base: string): Promise<void> {
  await b.page.goto(base, { waitUntil: 'networkidle0' })
  await b.page.waitForSelector('input[name=username]', { timeout: SHORT_WAIT_MS })
}

export async function signInAsAdmin(b: Browse): Promise<void> {
  await b.page.type('input[name=username]', ADMIN.username)
  await b.page.type('input[name=password]', ADMIN.password)
  await b.click('Sign in')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Overview', { timeout: SHORT_WAIT_MS })
}

export async function overviewPage(b: Browse): Promise<void> {
  await b.go('#/')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Overview', { timeout: SHORT_WAIT_MS })
}

export async function machinesPage(b: Browse): Promise<void> {
  await b.go('#/machines')
  await b.until(() => document.body.innerText.includes('rtx-5090') && document.body.innerText.includes('mac-studio'), { timeout: SHORT_WAIT_MS })
}

/** A machine with a GPU, online, with its numbers moving. It comes from the monitor's stand-in parent, because only it sends numbers. */
export async function livePage(b: Browse, standInBase: string): Promise<void> {
  await openMachine(b, standInBase, LIVE_MACHINE)
  await b.until(() => !!document.querySelector('[data-testid=cpu-total]'), { timeout: SHORT_WAIT_MS })
}

export async function vmsTab(b: Browse, base: string): Promise<void> {
  await openMachine(b, base, MAC)
  await openTab(b, 'VMs')
  await b.until(() => !!document.querySelector('section.bv'), { timeout: SHORT_WAIT_MS })
}

export async function allVmsWithCreate(b: Browse): Promise<void> {
  await b.go(`#/vms/create?machine=${MAC}`)
  await b.page.waitForSelector('dialog[open] #vm-create-name', { timeout: SHORT_WAIT_MS })
}

export async function offlineMachine(b: Browse, base: string): Promise<void> {
  await openMachine(b, base, OFFLINE)
}

/** The Check step with ticks and crosses. The parent's answer is made up here, because the test computer is always a ready Mac: it misses Incus and Python. */
function failingAnswer(fingerprint: string) {
  const requirements = [PASSING('login', 'Login'), PASSING('system', 'System'), PASSING('vm_support', 'Can run workloads'), MISSING_INCUS, MISSING_PYTHON]
  return { host: LOOPBACK, fingerprint, facts: LINUX_FACTS, requirements, can_add: false, isolation: ['folder'], system: 'Ubuntu 24.04 · AMD Ryzen 9 5950X · x86_64' }
}

const dialogSays = (b: Browse, pattern: RegExp) =>
  b.until((source) => new RegExp(source, 'i').test(document.querySelector<HTMLElement>('dialog[open]')?.innerText ?? ''), { timeout: STEP_WAIT_MS }, pattern.source)

/** Find machines, Scan now, Add on the found row, Look at it, a user name, Log in and check. Returns a function that stops the made-up answer. */
export async function addMachineCheck(b: Browse, sshPort: number, fingerprint: string): Promise<() => Promise<void>> {
  await b.go('#/machines/find')
  await b.until(() => document.body.innerText.includes('Looks at'), { timeout: SHORT_WAIT_MS })
  await b.click('Scan now')
  await b.page.waitForSelector(`button[aria-label="Add ${FOUND_ADDRESS}"]`, { timeout: STEP_WAIT_MS })
  await b.page.click(`button[aria-label="Add ${FOUND_ADDRESS}"]`)
  await b.page.waitForSelector('dialog[open] #connect-host')
  await b.type('#connect-host', LOOPBACK)
  await b.type('#connect-port', String(sshPort))
  await b.click('Look at it')
  await dialogSays(b, /Found a computer at/)
  await b.type('#connect-user', 'luca')
  await b.page.setRequestInterception(true)
  const answer = async (request: HTTPRequest): Promise<void> => {
    if (!request.url().endsWith('/api/remote/verify')) return void (await request.continue())
    await request.respond({ status: 200, contentType: 'application/json', body: JSON.stringify(failingAnswer(fingerprint)) })
  }
  b.page.on('request', answer)
  await b.click('Log in and check')
  await dialogSays(b, /things? to fix before this computer can be added/)
  return async () => {
    b.page.off('request', answer)
    await b.page.setRequestInterception(false)
  }
}
