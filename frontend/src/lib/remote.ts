// What the Connect screen asks for and sends, as plain functions so they are easy to test. No DOM, no network.
import { relativeTime } from './format.ts'
import type { ConnectForm, RemoteMachineInfo, VerifyResult } from './types.ts'

const HOST = /^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$/
const USER = /^[A-Za-z_][A-Za-z0-9_.-]{0,31}$/
const SSH_PORT = 22
const LONGEST_PASSWORD = 256

export const emptyConnectForm = (host = ''): ConnectForm => ({ host, port: String(SSH_PORT), user: '', password: '', useKey: false })

export function portOf(form: ConnectForm): number | null {
  const port = Number(form.port)
  return Number.isInteger(port) && port >= 1 && port <= 65535 ? port : null
}

/** What is wrong with the computer's address, or null. Same rules as the control panel's, so a bad one never leaves the page. */
export function whereProblem(form: ConnectForm): string | null {
  if (!HOST.test(form.host.trim())) return 'Type the computer\'s address (for example 192.168.100.40) or its name.'
  if (portOf(form) === null) return 'The SSH port is a number from 1 to 65535 (usually 22).'
  return null
}

/** What is missing before the login can start, or null. */
export function loginProblem(form: ConnectForm): string | null {
  if (!USER.test(form.user)) return 'Type the user name you log in with on that computer.'
  if (!form.useKey && form.password === '') return 'Type the password, or choose to use the parent\'s key.'
  if (form.password.length > LONGEST_PASSWORD) return `The password is too long (at most ${LONGEST_PASSWORD} characters).`
  return null
}

export const probeBody = (form: ConnectForm) => ({ host: form.host.trim(), port: portOf(form) ?? SSH_PORT })

/** The login request. A password is sent only when the password way is chosen, and never together with the key. */
export function verifyBody(form: ConnectForm, fingerprint: string): Record<string, unknown> {
  const base = { ...probeBody(form), user: form.user, fingerprint }
  return form.useKey ? { ...base, use_key: true } : { ...base, password: form.password }
}

/** The fingerprint in groups, so a person can compare it with the other computer's by eye. */
export function groupedFingerprint(fingerprint: string): string {
  const [kind, value = ''] = fingerprint.split(':')
  return `${kind}:${value.match(/.{1,8}/g)?.join(' ') ?? ''}`
}

const ISOLATION_TEXT: Record<string, string> = {
  folder: 'In a folder of that user. No admin rights needed, and nothing else on the computer is touched.',
  dedicated_user: 'Under its own user. That needs admin rights (sudo) on that computer.',
}

export const isolationText = (level: string): string => ISOLATION_TEXT[level] ?? level

/** The choices of the "What will change" step. The machine's name is a machine id: the same rule as for a machine on this computer. The three advanced ones are left empty for the defaults. */
export interface AddChoices {
  name: string
  installKey: boolean
  /** Lets the panel see and control this computer's screen. Off unless ticked. */
  allowScreen: boolean
  box: string
  sshDir: string
  agentPort: string
}

const MACHINE_NAME = /^[a-z0-9][a-z0-9-]{0,62}$/
const PLAIN_PATH = /^\/[A-Za-z0-9._@+/-]{1,200}$/
const LOWEST_PORT = 1024
const HIGHEST_PORT = 65000

export const defaultAddChoices = (host: string): AddChoices => ({ name: suggestMachineName(host), installKey: true, allowScreen: false, box: '', sshDir: '', agentPort: '' })

/** A machine name from the address or host name: lowercase, letters, digits and dashes. */
export function suggestMachineName(host: string): string {
  const cleaned = host.toLowerCase().replace(/\.local$/, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 63).replace(/-+$/, '')
  return MACHINE_NAME.test(cleaned) ? cleaned : 'new-machine'
}

export const nameWrong = (name: string): string | null => (MACHINE_NAME.test(name) ? null : 'Use lowercase letters, numbers and dashes, starting with a letter or a number.')

const isPlainPath = (path: string): boolean => PLAIN_PATH.test(path) && !path.includes('//') && !path.split('/').some((part) => part === '..' || part === '.')

/** What is wrong with the advanced choices, or null. Same rules as the control panel's, so a bad one never leaves the page. */
export function advancedProblem(choices: AddChoices): string | null {
  if (choices.box !== '' && !isPlainPath(choices.box)) return 'The box folder must be a full path with letters, numbers and . _ @ + - only.'
  if (choices.sshDir !== '' && !isPlainPath(choices.sshDir)) return 'The SSH folder must be a full path with letters, numbers and . _ @ + - only.'
  const port = Number(choices.agentPort)
  if (choices.agentPort !== '' && !(Number.isInteger(port) && port >= LOWEST_PORT && port <= HIGHEST_PORT)) return `The port is a number from ${LOWEST_PORT} to ${HIGHEST_PORT}.`
  return null
}

/** The fields that both the plan and the install carry. An advanced choice that was left empty is not sent, so the default applies. */
function choiceFields(choices: AddChoices): Record<string, unknown> {
  const fields: Record<string, unknown> = { name: choices.name, install_key: choices.installKey }
  if (choices.allowScreen) fields.allow_screen = true
  if (choices.box !== '') fields.box = choices.box
  if (choices.sshDir !== '') fields.ssh_dir = choices.sshDir
  if (choices.agentPort !== '') fields.agent_port = Number(choices.agentPort)
  return fields
}

/** What the plan request needs from what Connect read: the system and the home folder, and the choices. */
export function planBody(form: ConnectForm, result: VerifyResult, choices: AddChoices): Record<string, unknown> {
  return { host: form.host.trim(), home: result.facts.home, os: result.facts.os === 'Darwin' ? 'Darwin' : 'Linux', ...choiceFields(choices) }
}

/** The install request: the same login as Connect (a password only when that way was chosen) plus the choices. */
export function addBody(form: ConnectForm, fingerprint: string, choices: AddChoices): Record<string, unknown> {
  return { ...verifyBody(form, fingerprint), ...choiceFields(choices) }
}

/** The removal request: log in once more to take MetaService off the computer, or only forget the machine here. */
export function removeBody(form: ConnectForm, forgetOnly: boolean): Record<string, unknown> {
  if (forgetOnly) return { forget_only: true }
  return form.useKey ? { use_key: true } : { password: form.password }
}

/** One line about how the parent reaches a machine that was installed over SSH. */
export function connectionText(info: RemoteMachineInfo, now: number = Date.now()): string {
  const tunnel = info.tunnel
  if (!tunnel) return 'No tunnel: it reports in, but the parent cannot send it commands'
  const since = relativeTime(tunnel.since, now)
  if (tunnel.state === 'connected') return `SSH tunnel · connected ${since}`
  if (tunnel.state === 'connecting') return 'SSH tunnel · connecting…'
  return `SSH tunnel · down since ${since}, trying again${tunnel.failures > 1 ? ` (${tunnel.failures} tries)` : ''}`
}
