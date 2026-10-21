// A VM that never came up, in a real browser against a real parent and the Fake Agent (agent/fake): the failed order shows its reason, with the last lines the VM printed,
// in the "Creating" card as wrapped text; hostile text in it stays text; the card has no sideways scroll on a phone.
// Needs: the parent build, a built panel, Google Chrome, `bun install` in frontend/. FAKE_PYTHON is the python of `nix develop` (`nix develop --command which python3`).
// Run: SHOTS_DIR=<dir> bun e2e/start-failed.e2e.ts
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

const FAKE_PYTHON = process.env.FAKE_PYTHON ?? 'python3'
const MACHINE = 'fake-mac'
const WAIT_MS = 30000
const HELPER_START_MS = 1500
const HEARTBEAT_EVERY_MS = 5000
const PHONE = { width: 400, height: 900 }
const DESKTOP = { width: 1280, height: 900 }
const HOSTILE = '<img src=x onerror="window.__xss=1">'
const FAILURE = [
  'The VM did not start.',
  'Try 1, with systemd: it stopped right after it started (exit code 255). Its last lines:',
  'Failed to mount tmpfs (type tmpfs) on /run: Operation not permitted',
  '[!!!!!!] Failed to mount API filesystems.',
  'Try 2, without systemd: it did not start in time (60 seconds).',
  `${HOSTILE}\u001b[31mred\u001b[0m`,
].join('\n')

interface Helper { process: ChildProcess; beat: NodeJS.Timeout; port: number; commandToken: string }

async function startHelper(world: World): Promise<Helper> {
  const { base, agentBase } = world.root
  if (!world.session) throw new Error('seed the world first')
  const invite = await fetch(`${base}/api/enrollments`, { method: 'POST', headers: writeHeaders(base, world.session), body: JSON.stringify({ name: MACHINE }) })
  const enrollmentToken = textField(await readRecord(invite, 'invite'), 'enrollment_token', 'invite')
  const json = { 'Content-Type': 'application/json' }
  const enrolled = await readRecord(await fetch(`${agentBase}/v1/agents/enroll`, { method: 'POST', headers: json, body: JSON.stringify({ enrollment_token: enrollmentToken, name: MACHINE }) }), 'enroll')
  const commandToken = textField(enrolled, 'command_token', 'enroll')
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-fake-'))
  const tokenFile = join(dir, 'command.token')
  writeFileSync(tokenFile, commandToken)
  chmodSync(tokenFile, 0o600)
  const port = await freePort()
  const process = spawn(FAKE_PYTHON, ['-m', 'agent.fake', '--port', String(port), '--token-file', tokenFile], { cwd: repo, env: { ...globalThis.process.env, PYTHONPATH: repo }, stdio: 'ignore' })
  await wait(HELPER_START_MS)
  const machineToken = textField(enrolled, 'machine_token', 'enroll')
  const heartbeat = { facts: { os: 'macos', arch: 'arm64', cpu_cores: 10, ram_total_mb: 65536, disk_total_gb: 1000, free_ram_mb: 30000, free_disk_gb: 700, gpu: [], capabilities: { vm: true, container: false, gpu_in_vm: false, gpu_in_container: false } }, workloads: [], bundle_version: null, agent_port: port }
  const send = () => fetch(`${agentBase}/v1/agents/heartbeat`, { method: 'POST', headers: { ...json, Authorization: `Bearer ${machineToken}` }, body: JSON.stringify(heartbeat) }).catch(() => undefined)
  await send()
  return { process, beat: setInterval(send, HEARTBEAT_EVERY_MS), port, commandToken }
}

async function makeCreatesFail(helper: Helper): Promise<void> {
  const reply = await fetch(`http://127.0.0.1:${helper.port}/fake/create-fails`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${helper.commandToken}` }, body: JSON.stringify({ error: FAILURE }) })
  check('the fake helper is set to fail every create with a long reason', reply.status === 204, String(reply.status))
}

async function askForAVm(world: World): Promise<void> {
  if (!world.session) throw new Error('seed the world first')
  const reply = await fetch(`${world.root.base}/api/workloads`, { method: 'POST', headers: writeHeaders(world.root.base, world.session), body: JSON.stringify({ name: 'test', kind: 'vm', cpu: 1, ram_mb: 1024, disk_gb: 5, machine: MACHINE }) })
  check('the parent accepts the create order', reply.status === 202, String(reply.status))
}

const card = (b: Browse) => b.run(() => document.querySelector<HTMLElement>('.pending li.failed')?.innerText ?? '')
const noSidewaysScroll = (b: Browse) => b.run(() => document.documentElement.scrollWidth <= window.innerWidth)

async function theFailedCard(b: Browse, world: World): Promise<void> {
  await b.page.goto(`${world.root.base}/#/vms`, { waitUntil: 'networkidle0' })
  await b.until(() => document.querySelector('.pending li.failed') !== null, { timeout: WAIT_MS })
  const text = await card(b)
  check('the failed card says the VM did not start, and says why for each try', text.includes('The VM did not start.') && text.includes('Try 1, with systemd') && text.includes('Try 2, without systemd'), text)
  check('it shows the last lines the VM printed', text.includes('Failed to mount API filesystems.'), text)
  check('the lines stay on separate lines', await b.run(() => (document.querySelector<HTMLElement>('.pending li.failed .reason')?.innerText.split('\n').length ?? 0) >= 5))
  const harmless = await b.run(() => ({ xss: Reflect.get(window, '__xss') ?? 0, images: document.querySelectorAll('.pending img').length, shownAsText: (document.querySelector('.pending li.failed .reason')?.textContent ?? '').includes('<img src=x') }))
  check('hostile text in the reason stays text: nothing ran and no image was made', harmless.xss === 0 && harmless.images === 0 && harmless.shownAsText, JSON.stringify(harmless))
  check('colour codes from the VM are gone', !text.includes('\u001b') && !text.includes('[31m'))
  check('the card offers Dismiss', await b.run(() => [...document.querySelectorAll('.pending li.failed button')].some((button) => button.textContent?.trim() === 'Dismiss')))
  await b.shot('start-failed-card.png')
  await b.page.setViewport(PHONE)
  check('the failed card does not scroll sideways on a phone', await noSidewaysScroll(b))
  await b.shot('start-failed-card-phone.png', true)
  await b.page.setViewport(DESKTOP)
}

const world = await startWorld()
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true, args: ['--no-first-run'] })
let helper: Helper | null = null
try {
  const page = await browser.newPage()
  await page.setViewport(DESKTOP)
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }])
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error instanceof Error ? error.message : String(error)))
  const b = browse(page)
  await firstRun(b, world)
  await seed(world)
  await signInWithAWrongThenTheRightPassword(b, world)
  helper = await startHelper(world)
  await makeCreatesFail(helper)
  await askForAVm(world)
  await theFailedCard(b, world)
  check('no script errors', errors.length === 0, errors.join(' | '))
} finally {
  if (helper) {
    clearInterval(helper.beat)
    helper.process.kill()
  }
  await browser.close()
  stopWorld(world)
}
finish()
