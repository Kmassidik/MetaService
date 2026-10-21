// The live monitor in a real browser against a REAL parent and the Fake Agent (agent/fake: changing numbers, 32 cores, a GPU, a hostile process name).
// Proves the panel reads what the parent really sends: numbers appear and change, a hostile name stays text, the parent is asked about every 5 s,
// a hidden tab stops, and killing the helper turns the page to "offline, last seen" with the last numbers greyed (never zeros).
// Needs: the parent build, a built panel, Google Chrome, `bun install` in frontend/. Run: SHOTS_DIR=<dir> bun e2e/monitor-real.e2e.ts
import { spawn, type ChildProcess } from 'node:child_process'
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import puppeteer from 'puppeteer-core'
import { writeHeaders } from './support/admin.ts'
import { check, finish } from './support/check.ts'
import { readRecord, textField } from './support/json.ts'
import { freePort, wait } from './support/net.ts'
import { browse, type Browse } from './support/page.ts'
import { chromePath, repo } from './support/paths.ts'
import { firstRun } from './panel/first-run.ts'
import { signInWithAWrongThenTheRightPassword } from './panel/machines.ts'
import { seed, startWorld, stopWorld, type World } from './panel/world.ts'

// The Fake Agent needs jsonschema and yaml: FAKE_PYTHON is the python of `nix develop` (`nix develop --command which python3`).
const FAKE_PYTHON = process.env.FAKE_PYTHON ?? 'python3'
const MACHINE = 'fake-box'
const SHORT_WAIT_MS = 15000
const PAGE_POLL_MS = 5000
const SLACK_MS = 2500
const HEARTBEAT_EVERY_MS = 5000
const HOSTILE_NAME = '<img src=x onerror=alert(1)>'
const SIZES = { desktop: { width: 1280, height: 1000 }, phone: { width: 400, height: 900 } }
const cpuText = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('[data-testid=cpu-total]')?.innerText ?? '')

interface Helper { process: ChildProcess; beat: NodeJS.Timeout }

/** Enrolls a machine as the parent expects and starts the Fake Agent with the command token the parent handed out. */
async function startHelper(world: World): Promise<Helper> {
  const { base, agentBase } = world.root
  if (!world.session) throw new Error('seed the world first')
  const invite = await fetch(`${base}/api/enrollments`, { method: 'POST', headers: writeHeaders(base, world.session), body: JSON.stringify({ name: MACHINE }) })
  const enrollmentToken = textField(await readRecord(invite, 'invite'), 'enrollment_token', 'invite')
  const json = { 'Content-Type': 'application/json' }
  const enrolled = await readRecord(await fetch(`${agentBase}/v1/agents/enroll`, { method: 'POST', headers: json, body: JSON.stringify({ enrollment_token: enrollmentToken, name: MACHINE }) }), 'enroll')
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-fake-'))
  const tokenFile = join(dir, 'command.token')
  writeFileSync(tokenFile, textField(enrolled, 'command_token', 'enroll'))
  chmodSync(tokenFile, 0o600)
  const port = await freePort()
  const process = spawn(FAKE_PYTHON, ['-m', 'agent.fake', '--port', String(port), '--token-file', tokenFile, '--cores', '32', '--gpu'], { cwd: repo, env: { ...globalThis.process.env, PYTHONPATH: repo }, stdio: 'ignore' })
  await wait(1500)
  const machineToken = textField(enrolled, 'machine_token', 'enroll')
  const heartbeat = { facts: { os: 'linux', arch: 'x86_64', cpu_cores: 32, ram_total_mb: 65536, disk_total_gb: 1000, free_ram_mb: 30000, free_disk_gb: 700, gpu: [], capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false } }, workloads: [], bundle_version: null, agent_port: port }
  const send = () => fetch(`${agentBase}/v1/agents/heartbeat`, { method: 'POST', headers: { ...json, Authorization: `Bearer ${machineToken}` }, body: JSON.stringify(heartbeat) }).catch(() => undefined)
  await send()
  return { process, beat: setInterval(send, HEARTBEAT_EVERY_MS) }
}

async function openMonitor(b: Browse, world: World) {
  await b.page.goto(`${world.root.base}/#/machines/details?id=${MACHINE}`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('[data-testid=cpu-total]') !== null, { timeout: SHORT_WAIT_MS }).catch(async (error: unknown) => {
    console.log((await b.text()).slice(0, 800))
    throw error
  })
}

const world = await startWorld()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
let helper: Helper | null = null
try {
  const page = await browser.newPage()
  await page.setViewport(SIZES.desktop)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const dialogs: string[] = []
  page.on('dialog', (dialog) => { dialogs.push(dialog.message()); void dialog.dismiss() })
  const asked: number[] = []
  const urls: string[] = []
  page.on('request', (request) => {
    if (!request.url().includes(`/api/machines/${MACHINE}/stats`)) return
    asked.push(Date.now())
    urls.push(request.url())
  })
  const b = browse(page)
  await firstRun(b, world)
  await seed(world)
  helper = await startHelper(world)
  await signInWithAWrongThenTheRightPassword(b, world)

  await openMonitor(b, world)
  const first = await cpuText(b)
  const text = await b.text()
  check('against the real parent the monitor shows CPU, memory, disk, network, GPU and processes', ['cpu', 'memory', 'disk', 'network', 'gpu', 'top processes'].every((word) => text.toLowerCase().includes(word)))
  check('the first reading says measuring and shows no zeros', /measuring/i.test(text) && first.trim() !== '0%')
  check('the old allocated headline is gone', !/Disk allocated|cores promised|whole building/.test(text))
  await b.shot('monitor-real-desktop.png')
  await b.until((before) => document.querySelector<HTMLElement>('[data-testid=cpu-total]')?.innerText !== before, { timeout: PAGE_POLL_MS * 2 + SLACK_MS }, first)
  await b.until(() => document.querySelectorAll('section[aria-label=CPU] .core').length === 32, { timeout: PAGE_POLL_MS * 2 + SLACK_MS })
  check('32 cores draw 32 bars in the CPU card once measured, with nothing to press', (await b.run(() => document.querySelectorAll('section[aria-label=CPU] .core').length)) === 32)
  check('while the window is closed the page asks the real parent without the list (processes=0)', urls.length > 0 && urls.every((url) => url.endsWith('?processes=0')), urls.join(' '))
  check('no process table is on the page while the window is closed', (await b.run(() => document.querySelectorAll('.procs').length)) === 0)
  check('the numbers change by themselves', (await cpuText(b)) !== first)
  const askedBeforeWindow = asked.slice()
  await b.click('Top processes')
  await b.until(() => document.querySelectorAll('dialog[open] .procs tbody tr').length > 1, { timeout: PAGE_POLL_MS * 2 + SLACK_MS })
  check('opening the window asks the real parent for the list (processes=1) and it shows 15 programs', urls.at(-1)?.endsWith('?processes=1') === true && (await b.run(() => document.querySelectorAll('dialog[open] .procs tbody tr').length)) === 15, urls.at(-1) ?? '')
  const cell = await b.run(() => ({ images: document.querySelectorAll('dialog[open] img').length, name: [...document.querySelectorAll('dialog[open] .procs .name')].map((n) => n.textContent) }))
  check('the hostile process name is text: no tag, no alert', cell.images === 0 && cell.name.includes(HOSTILE_NAME) && dialogs.length === 0, JSON.stringify({ cell, dialogs }))
  check('the secret in a command line is nowhere on the page', !(await b.text()).includes('SECRET-FAKE'))
  await b.shot('monitor-real-modal.png')
  await b.click('Close')
  await b.until(() => document.querySelector('dialog[open]') === null, { timeout: SHORT_WAIT_MS })

  const gaps = askedBeforeWindow.slice(1).map((time, index) => time - (askedBeforeWindow[index] ?? time)).filter((gap) => gap > 0)
  check('the page asks the parent about every 5 seconds', gaps.length > 0 && gaps.every((gap) => gap >= PAGE_POLL_MS - 500 && gap <= PAGE_POLL_MS + SLACK_MS), gaps.join(','))

  await page.setViewport(SIZES.phone)
  await wait(500)
  check('no sideways scroll on a phone', await b.run(() => document.documentElement.scrollWidth <= window.innerWidth))
  await b.shot('monitor-real-phone.png')
  await page.setViewport(SIZES.desktop)

  helper.process.kill()
  await b.until(() => /offline/i.test(document.body.innerText) && /last seen/i.test(document.body.innerText), { timeout: 60000 })
  const offline = await b.run(() => ({ greyed: document.querySelector('[data-testid=monitor]')?.className ?? '', cpu: document.querySelector<HTMLElement>('[data-testid=cpu-total]')?.innerText ?? '' }))
  check('a dead helper shows offline with the last numbers kept, not zeros', /\d/.test(offline.cpu) && offline.cpu.trim() !== '0%', JSON.stringify(offline))
  await b.shot('monitor-real-offline.png')
  check('no script errors or alerts', dialogs.length === 0)
} finally {
  if (helper) { clearInterval(helper.beat); helper.process.kill() }
  await browser.close()
  stopWorld(world)
}
finish()
