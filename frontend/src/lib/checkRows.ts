// The check list of "Add a machine" as the panel shows it: grouped in cards, a short label, a short value for a tick, one plain sentence for a cross.
// The parent's words (label, detail, fix) are API text and stay as they are: this module only reads them, and any row it does not know is shown with them unchanged.
// Pure functions: no DOM, no network.
import type { InstallOffer, Requirement } from './types.ts'

export type CheckGroup = 'computer' | 'software' | 'connection' | 'other'
/** ready: a tick. blocking: a cross that stops the computer from being added. optional: a cross that does not. */
export type RowState = 'ready' | 'blocking' | 'optional'

export interface ManualSteps {
  text: string
  commands: string[]
}

export interface CheckRow {
  id: string
  group: CheckGroup
  label: string
  state: RowState
  /** The short text on the right of a tick. Empty when the parent's text is too long to be short. */
  value: string
  /** What a cross says (one sentence), or a tick's detail when it has no short value. */
  sentence: string
  manual: ManualSteps | null
  install?: InstallOffer
}

export interface CheckCard {
  id: CheckGroup
  title: string
  rows: CheckRow[]
  hasBlocking: boolean
}

export type Tone = 'ready' | 'optional' | 'blocking'

const SHORT_VALUE_MAX = 24
const STOPPED_AFTER_ROWS = 2
const HOST_KEY_HEAD = 11
const HOST_KEY_TAIL = 8
const HOST_KEY_SHORT_MAX = 20
const SYSTEM_ID = 'system'
/** The rows whose cross does not stop the computer from being added. The parent decides this too (`optionalRows`); the panel only needs it to draw the cross calmly. */
const OPTIONAL_IDS: ReadonlySet<string> = new Set(['gpu_toolkit'])

const GROUPS: { id: CheckGroup; title: string }[] = [
  { id: 'computer', title: 'This computer' },
  { id: 'software', title: 'Software it needs' },
  { id: 'connection', title: 'Connection' },
  { id: 'other', title: 'Other checks' },
]

const GROUP_OF: Record<string, CheckGroup> = {
  login: 'computer', system: 'computer', agent: 'computer', memory: 'computer', disk: 'computer', vm_support: 'computer',
  vm_tool: 'software', gpu_toolkit: 'software', python: 'software', admin: 'software',
  port: 'connection', parent: 'connection',
}

const LABEL_OF: Record<string, string> = {
  agent: 'MetaService program',
  admin: 'Admin rights',
  parent: 'Parent can reach it',
  gpu_toolkit: 'NVIDIA toolkit for containers',
}

type Reader = (detail: string) => string | null

const firstGroup = (pattern: RegExp): Reader => (detail) => pattern.exec(detail)?.[1] ?? null
const whenMatches = (pattern: RegExp, value: string): Reader => (detail) => (pattern.test(detail) ? value : null)
const firstOf = (...readers: Reader[]): Reader => (detail) => {
  for (const read of readers) {
    const value = read(detail)
    if (value !== null) return value
  }
  return null
}

/** What a tick says in a few words, from the parent's detail. null means "not the text I expect": the generic rule takes over. */
const TICK_VALUE: Record<string, Reader> = {
  login: firstGroup(/^Logged in as (.+?)\. Host key /),
  system: (detail) => detail.split(' · ')[0] || null,
  agent: firstGroup(/\((.+?)\)/),
  memory: firstGroup(/^(\d+ GB)\.?$/),
  disk: firstGroup(/^(\d+ GB) free/),
  vm_support: firstOf(firstGroup(/: (VMs and containers)\./), whenMatches(/^Containers only/, 'Containers only'), whenMatches(/^Apple Silicon/, 'Apple Silicon')),
  vm_tool: whenMatches(/^Installed/, 'Installed'),
  gpu_toolkit: whenMatches(/^Installed/, 'Installed'),
  python: whenMatches(/^Found/, 'Found'),
  admin: firstGroup(/^(Yes, with a password|Yes|No)\b/),
  port: firstOf(whenMatches(/^Nothing uses it/, 'Free'), whenMatches(/^MetaService's own program/, 'Ours, replaced'), whenMatches(/^Could not check/, 'Not checked')),
  parent: () => 'Yes',
}

const APPLE_TOOL_NOT_THERE = "Apple's container tool makes the VMs. It is not installed on this computer."
const INCUS_NOT_THERE = 'Incus is the tool that makes the VMs. It is not installed on this computer.'
const WINDOWS_SENTENCE = 'Windows is not supported yet. Please use a Linux or Mac computer for now.'
const SYSTEM_SENTENCE = 'This kind of computer is not supported yet. MetaService runs on Mac and Linux computers.'

const neededAmount = (detail: string): string | null => /need at least (\d+ GB)/.exec(detail)?.[1] ?? null

function memorySentence(req: Requirement): string | null {
  if (/Could not read/.test(req.detail)) return 'MetaService could not read how much memory this computer has.'
  const need = neededAmount(req.detail)
  return need ? `This computer has too little memory. VMs need at least ${need}.` : null
}

function diskSentence(req: Requirement): string | null {
  if (/Could not read/.test(req.detail)) return 'MetaService could not read how much free disk space this computer has.'
  const need = neededAmount(req.detail)
  return need ? `This computer has too little free disk space. VMs need at least ${need}.` : null
}

function toolSentence(req: Requirement): string | null {
  if (/^Incus/.test(req.label)) return INCUS_NOT_THERE
  return /^Apple/.test(req.label) ? APPLE_TOOL_NOT_THERE : null
}

function toolkitSentence(req: Requirement): string {
  const card = /GPU \((.+?)\)/.exec(req.detail)?.[1]
  const what = card ? `the graphics card (${card})` : 'the graphics card'
  return `This small add-on lets containers use ${what}. It is missing, but you can still add the machine.`
}

const portSentence = (req: Requirement): string | null => {
  const port = /Port (\d+)/.exec(req.label)?.[1]
  return port ? `Something else already uses port ${port}. Stop it, then check again.` : null
}

const systemSentence = (req: Requirement): string => (/^Windows/.test(req.detail) ? WINDOWS_SENTENCE : SYSTEM_SENTENCE)

/** One plain sentence for a cross, without file paths or commands (those are in the manual steps). null: the parent's own detail is shown. */
const CROSS_SENTENCE: Record<string, (req: Requirement) => string | null> = {
  system: systemSentence,
  agent: () => 'MetaService has no helper program for this kind of computer yet, so it cannot be installed here.',
  memory: memorySentence,
  disk: diskSentence,
  vm_support: (req) => (/Apple Silicon/.test(req.detail) ? "Apple's container tool needs a Mac with Apple Silicon." : null),
  vm_tool: toolSentence,
  python: () => 'Python runs the chat. It is not installed on this computer.',
  gpu_toolkit: toolkitSentence,
  port: portSentence,
}

const COMMAND = /`([^`]+)`/g

/** The parent's "fix" text for a person who does it by hand: the text without backticks, and the real commands in it, to show in a code box. */
export function manualSteps(fix: string | undefined): ManualSteps | null {
  if (!fix) return null
  return { text: fix.replaceAll('`', ''), commands: [...fix.matchAll(COMMAND)].map((match) => match[1] ?? '') }
}

const stripEnd = (text: string): string => text.replace(/\.$/, '')

/** A tick: the short value when the panel knows this row, else the parent's detail itself when it is short, else the detail under the label. */
function tickText(req: Requirement): { value: string; sentence: string } {
  const known = TICK_VALUE[req.id]?.(req.detail) ?? null
  if (known !== null) return { value: known, sentence: '' }
  const plain = stripEnd(req.detail)
  return plain.length <= SHORT_VALUE_MAX ? { value: plain, sentence: '' } : { value: '', sentence: req.detail }
}

const crossText = (req: Requirement): { value: string; sentence: string } => ({ value: '', sentence: CROSS_SENTENCE[req.id]?.(req) ?? req.detail })

function stateOf(req: Requirement): RowState {
  if (req.ok) return 'ready'
  return OPTIONAL_IDS.has(req.id) ? 'optional' : 'blocking'
}

function rowOf(req: Requirement): CheckRow {
  const text = req.ok ? tickText(req) : crossText(req)
  const row: CheckRow = { id: req.id, group: GROUP_OF[req.id] ?? 'other', label: LABEL_OF[req.id] ?? req.label, state: stateOf(req), ...text, manual: req.ok ? null : manualSteps(req.fix) }
  return req.ok || !req.install ? row : { ...row, install: req.install }
}

/** The parent's requirements as rows, in the parent's order. */
export const checkRows = (requirements: Requirement[]): CheckRow[] => requirements.map(rowOf)

export const isBlocking = (row: CheckRow): boolean => row.state === 'blocking'

/** The cards that have rows, in a fixed order. A row the panel does not know goes to "Other checks". */
export function checkCards(rows: CheckRow[]): CheckCard[] {
  return GROUPS.map(({ id, title }) => {
    const inCard = rows.filter((row) => row.group === id)
    return { id, title, rows: inCard, hasBlocking: inCard.some(isBlocking) }
  }).filter((card) => card.rows.length > 0)
}

export const readyCount = (rows: CheckRow[]): { ready: number; total: number } => ({ ready: rows.filter((row) => row.state === 'ready').length, total: rows.length })

/** True when the check stopped at an unsupported system, so the rest was never looked at (a Windows computer shows only Login and System). */
export const stoppedEarly = (rows: CheckRow[]): boolean => rows.length <= STOPPED_AFTER_ROWS && rows.some((row) => row.id === SYSTEM_ID && isBlocking(row))

const things = (count: number): string => `${count} ${count === 1 ? 'thing' : 'things'}`

/** The one line under the machine's name: what is left to do before the computer can be added. */
export function verdict(rows: CheckRow[]): { tone: Tone; text: string } {
  const blocking = rows.filter(isBlocking)
  if (blocking.some((row) => row.id === SYSTEM_ID)) return { tone: 'blocking', text: 'This computer cannot be added: this kind of computer is not supported yet.' }
  if (blocking.length > 0) return { tone: 'blocking', text: `${things(blocking.length)} to fix before this computer can be added.` }
  if (rows.some((row) => row.state === 'optional')) return { tone: 'optional', text: 'Ready to add. One extra is missing, and it does not block adding.' }
  return { tone: 'ready', text: `All ${rows.length} checks passed. This computer can be added.` }
}

/** The host key in a short form, for a person to recognise it. The full key is what the Copy button copies. */
export const hostKeyShort = (fingerprint: string): string =>
  fingerprint.length <= HOST_KEY_SHORT_MAX ? fingerprint : `${fingerprint.slice(0, HOST_KEY_HEAD)}…${fingerprint.slice(-HOST_KEY_TAIL)}`
