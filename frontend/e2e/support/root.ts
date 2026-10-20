// Starts a real Root (the parent program) for a browser test, on free ports with its own database, and stops it again.
import { spawn, type ChildProcess } from 'node:child_process'
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { freePort, waitForHealth } from './net.ts'
import { agentBinary, fakesDir, panelDist, rootBinary } from './paths.ts'

/** A private network no test machine is on, so the scan of it never depends on the computer that runs the tests. */
export const SCAN_PREFIX = '10.231.77'

export interface RootOptions {
  /** Lines for the Root's env file, such as `ROOT_SETUP_TOKEN=...`. */
  envLines?: string[]
  /** More command-line options after the usual ones. */
  args?: string[]
  /** Extra variables for the Root's own process. */
  processEnv?: Record<string, string>
  /** Whether to print the Root's errors (set ROOT_LOG to see them). */
  logErrors?: boolean
}

export interface RunningRoot {
  base: string
  agentBase: string
  child: ChildProcess
  dir: string
  envFile: string
}

/** The settings that make the Find machines scan use the stand-in nmap and arp programs on `SCAN_PREFIX`. */
export function scanSettings(): { envLines: string[]; processEnv: Record<string, string> } {
  return {
    envLines: [`SCAN_SUBNET=${SCAN_PREFIX}.0/24`, `NMAP_PATH=${fakesDir}/fake_nmap.py`, `ARP_PATH=${fakesDir}/fake_arp.py`],
    processEnv: { FAKE_ARP_PREFIX: SCAN_PREFIX },
  }
}

export async function startRoot(options: RootOptions = {}): Promise<RunningRoot> {
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-'))
  const envFile = join(dir, 'root.env')
  writeFileSync(envFile, (options.envLines ?? []).map((line) => line + '\n').join(''))
  chmodSync(envFile, 0o600)
  const port = await freePort()
  const agentPort = await freePort()
  const base = `http://localhost:${port}`
  const args = ['--env-file', envFile, '--db', join(dir, 'db.sqlite3'), '--port', String(port), '--bind', '127.0.0.1', '--agent-port', String(agentPort), '--agent-bind', '127.0.0.1',
    '--agent-binary', agentBinary, '--public-url', base, '--ui-dir', panelDist, ...(options.args ?? [])]
  const errors = options.logErrors || process.env.ROOT_LOG ? 'inherit' : 'ignore'
  const child = spawn(rootBinary, args, { stdio: ['ignore', 'ignore', errors], env: { ...process.env, ...options.processEnv } })
  await waitForHealth(base, 'the Root')
  return { base, agentBase: `http://127.0.0.1:${agentPort}`, child, dir, envFile }
}
