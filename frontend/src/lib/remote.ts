// What the Connect screen asks for and sends, as plain functions so they are easy to test. No DOM, no network.
import { relativeTime } from './format.ts'
import type { ConnectForm, InstallOffer, RemoteMachineInfo, VerifyResult } from './types.ts'

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

/** What is wrong with the typed user name, or null. Empty is "missing", not "wrong": see userWarning. */
export function userWarning(user: string): string | null {
  if (user === '' || USER.test(user)) return null
  if (/\s/.test(user)) return 'A user name cannot have spaces. Use the short login name (for example "dalang"), not the full name shown on the login screen.'
  return 'A user name uses only letters, digits, dot, dash and underscore, and starts with a letter or underscore.'
}

/** What is missing before the login can start, or null. */
export function loginProblem(form: ConnectForm): string | null {
  if (!USER.test(form.user)) return 'Type the user name you log in with on that computer.'
  if (!form.useKey && form.password === '') return 'Type the password, or use MetaService\'s key instead.'
  if (form.password.length > LONGEST_PASSWORD) return `The password is too long (at most ${LONGEST_PASSWORD} characters).`
  return null
}

export const probeBody = (form: ConnectForm) => ({ host: form.host.trim(), port: portOf(form) ?? SSH_PORT })

/** The login request. A password is sent only when the password way is chosen, and never together with the key. */
export function verifyBody(form: ConnectForm, fingerprint: string): Record<string, unknown> {
  const base = { ...probeBody(form), user: form.user, fingerprint }
  return form.useKey ? { ...base, use_key: true } : { ...base, password: form.password }
}

/** True when "Install it for me" needs a typed password: the sudo one, and with a password login the login's own too (it was forgotten after the check). */
export const fixNeedsPassword = (form: ConnectForm, offer: InstallOffer): boolean => !form.useKey || offer.needs_password

/** What the password field is called, so the person knows which password it is. */
export const fixPasswordLabel = (form: ConnectForm): string => `Password of ${form.user} on that computer`

const FIX_WHAT: Record<string, string> = {
  vm_tool: 'Installs Incus (the tool that makes VMs) with apt, sets it up, and lets the login user use it.',
  python: 'Installs Python 3 with apt.',
  gpu_toolkit: "Adds NVIDIA's own package source and signing key to this computer (a source that is not part of the system), then installs NVIDIA's container toolkit from it with apt, so containers can use the GPU.",
  vm_packages: 'Installs qemu and its firmware with apt, and loads the KVM module, so this computer can run full VMs instead of only containers.',
}

const FIX_BUTTON: Record<string, string> = {
  gpu_toolkit: "Install it for me (adds NVIDIA's package source)",
}

/** The label of the button under a cross. The toolkit's says it adds a package source from NVIDIA, so the person knows before pressing. */
export const fixButtonLabel = (offer: InstallOffer): string => FIX_BUTTON[offer.part] ?? 'Install it for me'

export const fixWhat = (offer: InstallOffer): string => FIX_WHAT[offer.part] ?? 'Installs it with apt.'

/**
 * The "Install it for me" request: the login of Connect, which part, and the password. With a password login the one typed password is both the login and sudo;
 * with the key it is sudo only, and it is left out when sudo asks for none.
 */
export function fixBody(form: ConnectForm, fingerprint: string, offer: InstallOffer, typed: string): Record<string, unknown> {
  const login = verifyBody({ ...form, password: form.useKey ? '' : typed }, fingerprint)
  return offer.needs_password ? { ...login, fix: offer.part, sudo_password: typed } : { ...login, fix: offer.part }
}

/** True unless the computer said it takes only keys: then a password box would be a dead end. When it did not say, both ways are offered. */
export function passwordAccepted(methods: string[] | null | undefined): boolean {
  if (!methods || methods.length === 0) return true
  return methods.includes('password') || methods.includes('keyboard-interactive')
}

const PUBLIC_KEY = /^ssh-ed25519 [A-Za-z0-9+/]+={0,2}( [A-Za-z0-9._-]+)?$/

/**
 * One line to paste in a terminal on the other computer: it makes the folder, saves a copy of the key file, drops older lines
 * that carry the same label with a different key (every fresh start of MetaService makes a new key), adds this key once,
 * and fixes the permissions. Lines with any other label are never touched.
 * Null for anything that is not a plain public key, so nothing else is ever put into a command.
 */
export function keyCommand(publicKey: string): string | null {
  const key = publicKey.trim()
  if (!PUBLIC_KEY.test(key)) return null
  const [, blob = '', label = ''] = key.split(' ')
  const file = '~/.ssh/authorized_keys'
  const backup = `${file}.before-metaservice`
  const dropOld = label ? ` && cp ${file} ${backup} && awk -v k='${blob}' -v c='${label}' '!($NF==c && $2!=k)' ${backup} > ${file}` : ''
  return `mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ${file}${dropOld} && (grep -qxF '${key}' ${file} 2>/dev/null || echo '${key}' >> ${file}) && chmod 600 ${file} && echo 'Done: MetaService can log in now.'`
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
  box: string
  sshDir: string
  agentPort: string
}

const MACHINE_NAME = /^[a-z0-9][a-z0-9-]{0,62}$/
const PLAIN_PATH = /^\/[A-Za-z0-9._@+/-]{1,200}$/
const LOWEST_PORT = 1024
const HIGHEST_PORT = 65000

export const defaultAddChoices = (host: string): AddChoices => ({ name: suggestMachineName(host), installKey: true, box: '', sshDir: '', agentPort: '' })

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
