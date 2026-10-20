// A real OpenSSH server as this user on loopback, with a key-only login, so the tests that add a machine over SSH talk to a real one.
import { spawn, spawnSync, type ChildProcess } from 'node:child_process'
import { appendFileSync, chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { freePort, wait } from './net.ts'

const SSHD = '/usr/sbin/sshd'
const START_PAUSE_MS = 800

export interface TestSshd {
  port: number
  child: ChildProcess
  /** The file of keys that may log in: the test adds the parent's key to it. */
  authorized: string
  /** The server's host key fingerprint, as the panel must show it. */
  fingerprint: string
}

export async function startSshd(): Promise<TestSshd> {
  const dir = mkdtempSync(join(tmpdir(), 'ms-e2e-sshd-'))
  spawnSync('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', join(dir, 'host')])
  const authorized = join(dir, 'authorized_keys')
  writeFileSync(authorized, '')
  chmodSync(authorized, 0o600)
  const port = await freePort()
  const config = join(dir, 'config')
  writeFileSync(config, [`Port ${port}`, 'ListenAddress 127.0.0.1', `HostKey ${dir}/host`, `AuthorizedKeysFile ${authorized}`, 'PasswordAuthentication no', 'KbdInteractiveAuthentication no',
    'PubkeyAuthentication yes', 'UsePAM no', 'StrictModes no', `PidFile ${dir}/pid`, 'LogLevel ERROR'].join('\n') + '\n')
  // OpenSSH 9.8+ ignores an address for a while after failed logins; the test must not depend on that, so it is switched off where the server knows the setting.
  appendFileSync(config, 'PerSourcePenalties no\n')
  if (spawnSync(SSHD, ['-t', '-f', config]).status !== 0) writeFileSync(config, readFileSync(config, 'utf8').replace('PerSourcePenalties no\n', ''))
  const child = spawn(SSHD, ['-D', '-e', '-f', config], { stdio: 'ignore' })
  await wait(START_PAUSE_MS)
  const fingerprint = spawnSync('ssh-keygen', ['-lf', join(dir, 'host.pub')]).stdout.toString().split(' ')[1]
  if (!fingerprint) throw new Error("could not read the test server's host key fingerprint")
  return { port, child, authorized, fingerprint }
}
