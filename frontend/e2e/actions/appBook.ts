// The apps (OpenClaw, Hermes) the stand-in Root installs inside VMs after they start, and the image catalog that offers them.
// An install moves installing -> ready (or failed) as the VM page asks about it; a test can also finish one by hand. The answers have the shape the parent promises.
import type { BookAnswer } from './sshKeyBook.ts'

export type CatalogMode = 'ready' | 'old_helper'
export type AppProgress = 'installing' | 'ready' | 'failed'

export const APP_CAPTION = 'Installs after the VM starts, about 2 minutes'
export const OLD_HELPER_REASON = 'Update the helper on this machine first'
const STARTED_AT = 1_700_000_000
export const INSTALLED_VERSION = '2026.3.1'
export const APP_IDS = ['openclaw', 'hermes'] as const

/** Where the install of one VM is; `left` is how many more GETs still see it installing. */
interface Held {
  app: string
  state: AppProgress
  left: number
  message: string | null
  logTail: string[]
}

export interface AppBook {
  /** What the image catalog says about OpenClaw and Hermes. */
  catalog: CatalogMode
  /** How many GETs of a VM's app still see it installing after it began (a retry waits for the same number). */
  installPolls: number
  /** When set, an install ends as failed with this message and `logTail`, instead of ready. */
  failure: string | null
  logTail: string[]
  /** How long the app routes and the create route take to answer. */
  delayMs: number
  /** Every request of the app routes, as "GET vm5" or "RETRY vm5", in order. */
  requests: string[]
  images: () => Record<string, unknown>
  /** Starts the install of an app in a VM, as the parent does when a VM is created with a bundle. */
  begin: (vm: string, app: string) => void
  /** The app as the machine list reports it; null when the VM has none. */
  summary: (vm: string) => Record<string, unknown> | null
  view: (vm: string) => BookAnswer
  retry: (vm: string, running: boolean) => BookAnswer
  /** Ends an install without waiting for a GET. */
  finish: (vm: string) => void
  reset: () => void
}

const DEFAULTS = { catalog: 'ready', installPolls: 2, failure: null, logTail: [], delayMs: 0, requests: [] } as const
const NOT_RUNNING = { status: 409, body: { error: { code: 'not_running', message: 'Start the VM first.' } } } satisfies BookAnswer
const NO_APP = { status: 409, body: { error: { code: 'no_app', message: 'This VM has no app to install.' } } } satisfies BookAnswer

const stock = { id: 'blank', title: 'Blank (plain Ubuntu)', description: 'Plain.', state: 'ready', ready: true, available: true, reason: null }
const entry = (id: string, title: string, mode: CatalogMode): Record<string, unknown> => ({
  id,
  title,
  description: APP_CAPTION,
  state: 'ready',
  ready: mode === 'ready',
  available: mode === 'ready',
  reason: mode === 'ready' ? null : OLD_HELPER_REASON,
})

export function createAppBook(): AppBook {
  const held = new Map<string, Held>()
  const book: AppBook = {
    ...DEFAULTS,
    requests: [],
    logTail: [],
    images: () => ({ helper: book.catalog === 'ready' ? 'answered' : 'old_helper', images: [stock, entry('openclaw', 'OpenClaw', book.catalog), entry('hermes', 'Hermes', book.catalog)] }),
    begin(vm, app) {
      held.set(vm, { app, state: 'installing', left: book.installPolls, message: null, logTail: [] })
    },
    summary(vm) {
      const now = held.get(vm)
      return now ? { name: now.app, state: now.state, message: now.message } : null
    },
    view(vm) {
      book.requests.push(`GET ${vm}`)
      const now = held.get(vm)
      if (now?.state === 'installing') advance(vm, now)
      return { status: 200, body: answer(now) }
    },
    retry(vm, running) {
      book.requests.push(`RETRY ${vm}`)
      const now = held.get(vm)
      if (!now) return NO_APP
      if (!running) return NOT_RUNNING
      book.begin(vm, now.app)
      return { status: 200, body: answer(held.get(vm)) }
    },
    finish(vm) {
      const now = held.get(vm)
      if (now) conclude(now)
    },
    reset() {
      held.clear()
      Object.assign(book, DEFAULTS, { requests: [], logTail: [] })
    },
  }

  function conclude(now: Held): void {
    const failed = book.failure !== null
    now.state = failed ? 'failed' : 'ready'
    now.message = book.failure
    now.logTail = failed ? book.logTail : []
  }

  /** Every GET while installing uses up one poll; when none is left the install ends. */
  function advance(vm: string, now: Held): void {
    if (now.left > 0) now.left -= 1
    else conclude(now)
    held.set(vm, now)
  }

  function answer(now: Held | undefined): Record<string, unknown> {
    if (!now) return { app: null, state: 'none', message: null, log_tail: [], version: null, started_at: null }
    return { app: now.app, state: now.state, message: now.message, log_tail: now.logTail, version: now.state === 'ready' ? INSTALLED_VERSION : null, started_at: STARTED_AT }
  }

  return book
}
