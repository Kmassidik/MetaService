// One action of one button as a small state machine: idle -> busy -> done | failed -> idle.
// Pure: no page, no timers of its own (the clock is handed in), so every rule is tested without a browser.
import { FAILED_MESSAGE, MIN_BUSY_MS, REQUEST_TIMEOUT_MS, SUCCESS_LINE_MS, TIMEOUT_MESSAGE } from './timeouts.ts'

export type ActionStatus = 'idle' | 'busy' | 'done' | 'failed'

export interface ActionView {
  status: ActionStatus
  /** The plain failure text when failed, else empty. */
  message: string
}

export interface ActionClock {
  now: () => number
  /** Calls `run` after `ms`; the returned function cancels it. */
  after: (ms: number, run: () => void) => () => void
}

export interface ActionOptions {
  clock?: ActionClock
  /** How long a hung call may keep the action busy. */
  timeoutMs?: number
}

export interface Action {
  view: () => ActionView
  /** Starts the work, or does nothing and answers the call already running. Never rejects. */
  run: (work: () => Promise<unknown>) => Promise<void>
  subscribe: (listener: (view: ActionView) => void) => () => void
}

interface Outcome {
  failure: string | null
}

const IDLE: ActionView = { status: 'idle', message: '' }
const DONE: ActionView = { status: 'done', message: '' }

const realClock: ActionClock = {
  now: () => Date.now(),
  after(ms, run) {
    const id = setTimeout(run, ms)
    return () => clearTimeout(id)
  },
}

/** The small line next to the button: the failure, the success text for a moment, or nothing. */
export function lineOf(view: ActionView, doneText: string): string {
  if (view.status === 'failed') return view.message
  return view.status === 'done' ? doneText : ''
}

const failureText = (error: unknown): string => (error instanceof Error && error.message ? error.message : FAILED_MESSAGE)

export function createAction(options: ActionOptions = {}): Action {
  const clock = options.clock ?? realClock
  const timeoutMs = options.timeoutMs ?? REQUEST_TIMEOUT_MS
  const listeners = new Set<(view: ActionView) => void>()
  let current: ActionView = IDLE
  let inFlight: Promise<void> | null = null
  let cancelIdle: () => void = () => {}

  function set(next: ActionView): void {
    current = next
    for (const listener of listeners) listener(current)
  }

  /** The work's own end, or the timeout, whichever comes first. */
  function outcomeOf(work: () => Promise<unknown>): Promise<Outcome> {
    return new Promise<Outcome>((resolve) => {
      const cancelTimeout = clock.after(timeoutMs, () => resolve({ failure: TIMEOUT_MESSAGE }))
      const finish = (outcome: Outcome) => {
        cancelTimeout()
        resolve(outcome)
      }
      Promise.resolve()
        .then(work)
        .then(() => finish({ failure: null }), (error: unknown) => finish({ failure: failureText(error) }))
    })
  }

  const waitFor = (ms: number): Promise<void> => (ms > 0 ? new Promise((resolve) => clock.after(ms, resolve)) : Promise.resolve())

  async function execute(work: () => Promise<unknown>): Promise<void> {
    const started = clock.now()
    cancelIdle()
    set({ status: 'busy', message: '' })
    const outcome = await outcomeOf(work)
    await waitFor(MIN_BUSY_MS - (clock.now() - started))
    inFlight = null
    if (outcome.failure !== null) return set({ status: 'failed', message: outcome.failure })
    set(DONE)
    cancelIdle = clock.after(SUCCESS_LINE_MS, () => set(IDLE))
  }

  return {
    view: () => current,
    run(work) {
      if (inFlight) return inFlight
      inFlight = execute(work)
      return inFlight
    },
    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
  }
}
