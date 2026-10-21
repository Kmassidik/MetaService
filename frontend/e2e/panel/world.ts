// What the panel test stands up around the browser: a stand-in AI provider, a real Root with two seeded machines, and real Agents on demand.
import { spawn, spawnSync, type ChildProcess } from 'node:child_process'
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs'
import { createServer, type Server } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { signIn, writeHeaders, type Session } from '../support/admin.ts'
import { readRecord, textField } from '../support/json.ts'
import { freePort } from '../support/net.ts'
import { agentBinary, chatBuilder } from '../support/paths.ts'
import { scanSettings, startRoot, type RunningRoot } from '../support/root.ts'

export const AI_KEY = 'sk-e2e-not-a-real-key-0123456789'
export const XSS = '<img src=x onerror="window.__xss=1">'
const BUNDLE_VERSIONS = ['0.1.0', '0.2.0']
const AI_MODEL = 'fake-model'
const SEEDED_MACHINES = ['dgx-spark', 'mac-mini']
const SIMULATED_RAM_ALLOWANCE_MB = '16384'
const SIMULATED_RAM_RESERVE_MB = '4096'
const SIMULATED_DISK_ALLOWANCE_GB = '200'
const SIMULATED_DISK_RESERVE_GB = '10'

/** The one machine that reports a host problem, to check the panel shows it with its fix. */
const PROBLEM = { code: 'bridge_blocked_by_firewall', message: 'VMs cannot get an IPv4 address: the bridge incusbr0 is not trusted.', fix: 'As root, run: metaservice-agent setup --yes' }

/** A stand-in AI provider. Set `failing` to make it refuse. */
export interface Provider {
  failing: boolean
  base: string
  server: Server
}

export interface World {
  provider: Provider
  root: RunningRoot
  /** Set after the browser has created the admin and `seed` has signed in. */
  session: Session | null
}

async function startProvider(): Promise<Provider> {
  const provider: Provider = { failing: false, base: '', server: createServer() }
  provider.server.on('request', (request, response) => {
    request.resume()
    const good = !provider.failing && request.headers.authorization === `Bearer ${AI_KEY}`
    response.writeHead(good ? 200 : 500, { 'Content-Type': 'application/json' })
    response.end(JSON.stringify(good ? { choices: [{ message: { content: 'ok' } }], usage: { prompt_tokens: 9, completion_tokens: 1 } } : { error: 'nope' }))
  })
  await new Promise<void>((done) => provider.server.listen(0, '127.0.0.1', done))
  const address = provider.server.address()
  if (address === null || typeof address === 'string') throw new Error('the stand-in provider has no port')
  provider.base = `http://127.0.0.1:${address.port}/v1`
  return provider
}

export async function startWorld(): Promise<World> {
  const provider = await startProvider()
  const bundleDir = join(mkdtempSync(join(tmpdir(), 'ms-e2e-bundles-')), 'bundles')
  for (const version of BUNDLE_VERSIONS) spawnSync('python3', [chatBuilder, '--version', version, '--out', bundleDir])
  const scan = scanSettings()
  const root = await startRoot({
    envLines: [...scan.envLines, `AI_BASE_URL=${provider.base}`, `AI_API_KEY=${AI_KEY}`, `AI_DEFAULT_MODEL=${AI_MODEL}`],
    args: ['--bundle-dir', bundleDir],
    processEnv: scan.processEnv,
  })
  return { provider, root, session: null }
}

export function stopWorld(world: World): void {
  world.root.child.kill()
  world.provider.server.close()
}

function heartbeat(name: string) {
  return {
    facts: { os: name === 'mac-mini' ? 'macos' : 'linux', arch: 'aarch64', cpu_cores: 10, ram_total_mb: 32768, disk_total_gb: 1000, free_ram_mb: 20000, free_disk_gb: 700, gpu: [],
      capabilities: { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }, problems: name === 'dgx-spark' ? [PROBLEM] : [] },
    workloads: [{ id: 'wl-1', name: 'demo', kind: 'vm', state: 'running', cpu: 2, ram_mb: 2048, disk_gb: 20, gpu_mode: 'none', address: XSS, bundle_version: '1.0.0' }],
    bundle_version: '1.0.0',
  }
}

/** Invites a machine and enrolls it as an Agent would (on the Agent listener). Answers its machine token. Until it sends a heartbeat the machine shows as offline. */
export async function enrollMachine(world: World, session: Session, name: string): Promise<string> {
  const { base, agentBase } = world.root
  const invite = await fetch(`${base}/api/enrollments`, { method: 'POST', headers: writeHeaders(base, session), body: JSON.stringify({ name }) })
  const enrollmentToken = textField(await readRecord(invite, 'invite'), 'enrollment_token', 'invite')
  const enrolled = await fetch(`${agentBase}/v1/agents/enroll`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enrollment_token: enrollmentToken, name }) })
  return textField(await readRecord(enrolled, 'enroll'), 'machine_token', 'enroll')
}

/** The last heartbeat each machine sent, so a slow test can send them again: a machine that stays silent for three beats shows as offline. */
const lastHeartbeats = new Map<string, unknown>()

/** Sends every machine's last heartbeat again, so the machines the test made online are still online. Machines that never sent one stay as they were (offline). */
export async function resendHeartbeats(world: World): Promise<void> {
  for (const [token, body] of lastHeartbeats) await sendHeartbeat(world, token, body)
}

/** One heartbeat from a machine, with whatever facts and VMs the test wants it to report. */
export async function sendHeartbeat(world: World, machineToken: string, body: unknown): Promise<void> {
  lastHeartbeats.set(machineToken, body)
  const reply = await fetch(`${world.root.agentBase}/v1/agents/heartbeat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${machineToken}` }, body: JSON.stringify(body) })
  if (!reply.ok) throw new Error(`the heartbeat was refused (${reply.status}): ${(await reply.text()).slice(0, 300)}`)
}

/** Signs in as the admin made on the first-run page, invites two machines and enrolls them as Agents would (on the Agent listener). */
export async function seed(world: World): Promise<Session> {
  const session = await signIn(world.root.base)
  world.session = session
  for (const name of SEEDED_MACHINES) await sendHeartbeat(world, await enrollMachine(world, session, name), heartbeat(name))
  return session
}

/** A real Agent (simulated engine, small known budget) enrolled under this name, so the Root has someone to send commands to. */
export async function startAgent(world: World, name = 'agent-mac'): Promise<ChildProcess> {
  const { base, agentBase } = world.root
  if (!world.session) throw new Error('seed the world before starting an Agent')
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-agent-'))
  const invite = await fetch(`${base}/api/enrollments`, { method: 'POST', headers: writeHeaders(base, world.session), body: JSON.stringify({ name, ip: '127.0.0.1' }) })
  const tokenFile = join(dir, 'enroll.token')
  writeFileSync(tokenFile, textField(await readRecord(invite, 'invite'), 'enrollment_token', 'invite'))
  chmodSync(tokenFile, 0o600)
  const enrolled = spawnSync(agentBinary, ['enroll', '--root', agentBase, '--name', name, '--enrollment-token-file', tokenFile, '--state-dir', dir])
  if (enrolled.status !== 0) throw new Error('agent enroll failed: ' + enrolled.stderr.toString())
  return spawn(agentBinary, ['run', '--state-dir', dir, '--port', String(await freePort()), '--bind', '127.0.0.1', '--engine', 'simulated', '--heartbeat-seconds', '1',
    '--ram-allowance-mb', SIMULATED_RAM_ALLOWANCE_MB, '--ram-reserve-mb', SIMULATED_RAM_RESERVE_MB, '--disk-allowance-gb', SIMULATED_DISK_ALLOWANCE_GB, '--disk-reserve-gb', SIMULATED_DISK_RESERVE_GB,
    '--chat-port', String(await freePort()), '--chat-bind', '127.0.0.1'], { stdio: 'ignore' })
}
