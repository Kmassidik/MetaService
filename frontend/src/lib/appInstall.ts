// The app (OpenClaw or Hermes) that is installed inside a VM after it starts: how the parent's answers are read, and the plain words for each state.
// Pure functions, no DOM, no network. Every text from the parent or from inside the VM is only ever shown as text.
import { isFields, optionalText, UnreadableAnswer, type Fields } from './unreadable.ts'
import type { LogoName } from './logos.ts'
import type { WorkloadApp } from './types.ts'

export type AppState = 'none' | 'installing' | 'ready' | 'failed'

/** The answer of GET /api/machines/{id}/workloads/{workload}/app. */
export interface AppView {
  /** The app's catalog id; null when the VM has none. */
  app: string | null
  state: AppState
  message: string | null
  logTail: string[]
  version: string | null
  startedAt: number | null
}

/** How the app chip next to a VM's status looks: busy (progress), ok (green) or bad (red). */
export type ChipTone = 'busy' | 'ok' | 'bad'

export interface AppChip {
  tone: ChipTone
  text: string
  /** The hover text: the failure message. Null when there is none. */
  title: string | null
  /** The visible line under the chip for a failure (phones have no hover). Null otherwise. */
  detail: string | null
}

/** The last lines of the install log that the VM page shows. */
export const LOG_LINES_SHOWN = 12
const APP_LOGOS: Readonly<Record<string, LogoName>> = { openclaw: 'openclaw', hermes: 'hermes' }
const APP_TITLES: Readonly<Record<string, string>> = { openclaw: 'OpenClaw', hermes: 'Hermes' }
const STATES: readonly AppState[] = ['none', 'installing', 'ready', 'failed']
const FALLBACK_TITLE = 'The app'

export const INSTALLING_TEXT = 'Installing… about 2 minutes'
export const READY_TEXT = 'Ready'
export const FAILED_FALLBACK_TEXT = 'The install did not finish.'
export const NO_APP_TEXT = 'No app is installed on this VM.'

/** The app's name as people know it; an id the panel does not know is shown as it came. */
export const appTitle = (name: string | null): string => (name === null ? FALLBACK_TITLE : (APP_TITLES[name] ?? name))

/** The logo to draw next to the app's name, or null for an app the panel has no logo for. */
export const appLogoName = (name: string | null): LogoName | null => (name === null ? null : (APP_LOGOS[name] ?? null))

function stateOf(source: Fields): AppState {
  const found = STATES.find((known) => known === source.state)
  if (found === undefined) throw new UnreadableAnswer('state is not one of the promised words')
  return found
}

function lines(source: Fields): string[] {
  const value = source.log_tail ?? []
  if (!Array.isArray(value) || value.some((line) => typeof line !== 'string')) throw new UnreadableAnswer('log_tail is not a list of text')
  return value.map(String)
}

function whole(source: Fields, key: string): number | null {
  const value = source[key]
  if (value === null || value === undefined) return null
  if (typeof value === 'number' && Number.isInteger(value)) return value
  throw new UnreadableAnswer(`${key} is not a whole number`)
}

/** Reads the parent's answer. Anything that is not the promised shape throws UnreadableAnswer. */
export function parseAppView(raw: unknown): AppView {
  if (!isFields(raw)) throw new UnreadableAnswer('the app answer is not an object')
  return { app: optionalText(raw, 'app'), state: stateOf(raw), message: optionalText(raw, 'message'), logTail: lines(raw), version: optionalText(raw, 'version'), startedAt: whole(raw, 'started_at') }
}

/** The chip for the app in a machine list's workload; null when the VM has no app (or the state is one the chip does not show). */
export function appChip(app: WorkloadApp | null | undefined): AppChip | null {
  if (!app) return null
  const title = appTitle(app.name)
  if (app.state === 'installing') return { tone: 'busy', text: `Installing ${title}…`, title: null, detail: null }
  if (app.state === 'ready') return { tone: 'ok', text: `${title} ready`, title: null, detail: null }
  if (app.state === 'failed') return { tone: 'bad', text: `${title} install failed`, title: app.message, detail: app.message }
  return null
}

/** The state line of the VM page's Software block. */
export function stateLine(view: AppView): string {
  if (view.state === 'installing') return INSTALLING_TEXT
  if (view.state === 'ready') return READY_TEXT
  if (view.state === 'failed') return view.message ?? FAILED_FALLBACK_TEXT
  return NO_APP_TEXT
}

/** The last lines of the log, at most LOG_LINES_SHOWN. */
export const shownLog = (view: AppView): string[] => view.logTail.slice(-LOG_LINES_SHOWN)

/** The page asks again while the app is installing, and stops at any other state. */
export const shouldPollApp = (view: AppView | null): boolean => view?.state === 'installing'

/** True when the Software block has something to show: a VM without an app has no block. */
export const hasApp = (view: AppView | null): boolean => view !== null && view.app !== null && view.state !== 'none'
