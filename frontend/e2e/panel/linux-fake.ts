// A Linux-flavoured fake helper (agent/fake, which serves a /bin/sh console) enrolled under a name, so the panel's Terminal button can be tried on a Linux machine
// that says it serves a terminal and on one that does not. It tells the Root what it is the way a helper does: facts, workloads and its port.
import { spawn, type ChildProcess } from 'node:child_process'
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { writeHeaders } from '../support/admin.ts'
import { isRecord, readRecord, textField, type Json } from '../support/json.ts'
import { freePort, wait } from '../support/net.ts'
import { repo } from '../support/paths.ts'
import { sendHeartbeat, type World } from './world.ts'

/** The Fake Agent needs jsonschema and yaml: FAKE_PYTHON is the python of `nix develop` (`nix develop --command which python3`). */
const FAKE_PYTHON = process.env.FAKE_PYTHON ?? 'python3'
const START_TRIES = 100
const START_PAUSE_MS = 100

export interface LinuxFake {
  child: ChildProcess
  /** The ids the fake gave its workloads, in the order they were asked for. */
  workloads: string[]
}

export interface LinuxFakeOptions {
  /** Whether the helper says `terminal` in its capabilities. */
  terminal: boolean
  /** NAME:KIND for each running workload. */
  workloads: string[]
}

async function enrollWithCommandToken(world: World, name: string): Promise<{ machineToken: string; commandToken: string }> {
  const { base, agentBase } = world.root
  if (!world.session) throw new Error('seed the world before starting a fake helper')
  const invite = await fetch(`${base}/api/enrollments`, { method: 'POST', headers: writeHeaders(base, world.session), body: JSON.stringify({ name }) })
  const enrollmentToken = textField(await readRecord(invite, 'invite'), 'enrollment_token', 'invite')
  const enrolled = await fetch(`${agentBase}/v1/agents/enroll`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enrollment_token: enrollmentToken, name }) })
  const record = await readRecord(enrolled, 'enroll')
  return { machineToken: textField(record, 'machine_token', 'enroll'), commandToken: textField(record, 'command_token', 'enroll') }
}

/** Asks the fake helper, waiting for it to start listening (it is a Python program that has just been launched). */
async function ask(port: number, token: string, path: string): Promise<Json> {
  for (let attempt = 0; attempt < START_TRIES; attempt++) {
    const reply = await fetch(`http://127.0.0.1:${port}${path}`, { headers: { Authorization: `Bearer ${token}` } }).catch(() => null)
    if (reply?.ok) return readRecord(reply, path)
    await wait(START_PAUSE_MS)
  }
  throw new Error(`the Linux fake helper did not answer ${path}`)
}

export async function startLinuxFake(world: World, name: string, options: LinuxFakeOptions): Promise<LinuxFake> {
  const { machineToken, commandToken } = await enrollWithCommandToken(world, name)
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-linux-fake-'))
  const tokenFile = join(dir, 'command.token')
  writeFileSync(tokenFile, commandToken)
  chmodSync(tokenFile, 0o600)
  const port = await freePort()
  const flags = ['--os', 'linux', ...(options.terminal ? [] : ['--no-terminal']), ...options.workloads.flatMap((workload) => ['--workload', workload])]
  const child = spawn(FAKE_PYTHON, ['-m', 'agent.fake', '--port', String(port), '--token-file', tokenFile, ...flags], { cwd: repo, env: { ...globalThis.process.env, PYTHONPATH: repo }, stdio: 'ignore' })
  const facts = await ask(port, commandToken, '/v1/facts')
  const listed = await ask(port, commandToken, '/v1/workloads')
  const workloads = Array.isArray(listed.workloads) ? listed.workloads.filter(isRecord) : []
  await sendHeartbeat(world, machineToken, { facts, workloads, agent_port: port, bundle_version: null })
  return { child, workloads: workloads.map((workload) => textField(workload, 'id', 'workload')) }
}
