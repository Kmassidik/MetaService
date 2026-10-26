// One action of one button as a small state machine: idle -> busy -> done | failed -> idle.
// A throttle answer (HTTP 429) adds a cooldown: the button says to wait and starts nothing until it ends.
// Pure: no page, no timers of its own (the clock is handed in), so every rule is tested without a browser.
import { FAILED_MESSAGE, MIN_BUSY_MS, REQUEST_TIMEOUT_MS, SUCCESS_LINE_MS, THROTTLE_COOLDOWN_MS, TIMEOUT_MESSAGE } from './timeouts.ts'

export type ActionStatus = 'idle' | 'busy' | 'done' | 'failed'

export interface ActionView {
  status: ActionStatus
  /** The plain failure text when failed, else empty. */
  message: string
  /** A throttle refusal: the button starts nothing until the cooldown ends. */
  cooling: boolean
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
  /** How long a throttle answer keeps the action from running again. */
  cooldownMs?: number
}

export interface Action {
  view: () => ActionView
  /** Starts the work, or does nothing and answers the call already running. Never rejects. */
  run: (work: () => Promise<unknown>) => Promise<void>
  /** Forgets the last answer and frees the button; a run still in flight is ignored when it ends. */
  reset: () => void
  subscribe: (listener: (view: ActionView) => void) => () => void
}

interface Outcome {
  failure: string | null
  throttled: boolean
}

/** The button's words while a throttle answer keeps it waiting. */
export const COOLING_LABEL = 'Wait a moment…'
/** What to do after a throttle refusal. */
export const RETRY_LINE = 'Try again in a moment.'

const IDLE: ActionView = { status: 'idle', message: '', cooling: false }
const DONE: ActionView = { status: 'done', message: '', cooling: false }
/** The parent's throttle answers with this status: too many tries, so waiting is the only way forward. */
const THROTTLE_STATUS = 429

const realClock: ActionClock = {
  now: () => Date.now(),
  after(ms, run) {
    const id = setTimeout(run, ms)
    return () => clearTimeout(id)
  },
}

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null

/** True when the answer is the parent's throttle, whatever carries it: too many tries on that computer, so a second press cannot help. */
export function isThrottleAnswer(error: unknown): boolean {
  return isRecord(error) && error.status === THROTTLE_STATUS
}

/** The small line next to the button: the failure, the success text for a moment, or nothing. */
export function lineOf(view: ActionView, doneText: string): string {
  if (view.status === 'failed') return view.message
  return view.status === 'done' ? doneText : ''
}

/** The button's own words: what is happening while it runs, the wait during a cooldown, or its plain label. */
export function actionLabel(view: ActionView, idle: string, busy: string): string {
  if (view.status === 'busy') return busy
  return view.cooling ? COOLING_LABEL : idle
}

/** What to do after a throttle refusal, or nothing when the button is free. */
export const retryLine = (view: ActionView): string => (view.cooling ? RETRY_LINE : '')

const failureText = (error: unknown): string => (error instanceof Error && error.message ? error.message : FAILED_MESSAGE)

export function createAction(options: ActionOptions = {}): Action {
  const clock = options.clock ?? realClock
  const timeoutMs = options.timeoutMs ?? REQUEST_TIMEOUT_MS
  const cooldownMs = options.cooldownMs ?? THROTTLE_COOLDOWN_MS
  const listeners = new Set<(view: ActionView) => void>()
  let current: ActionView = IDLE
  let inFlight: Promise<void> | null = null
  let cancelIdle: () => void = () => {}
  let cancelCooldown: () => void = () => {}
  /** Bumped by every run and every reset, so a run that was forgotten cannot change the screen when it ends. */
  let generation = 0

  function set(next: ActionView): void {
    current = next
    for (const listener of listeners) listener(current)
  }

  function stopTimers(): void {
    cancelIdle()
    cancelCooldown()
  }

  /** The work's own end, or the timeout, whichever comes first. */
  function outcomeOf(work: () => Promise<unknown>): Promise<Outcome> {
    return new Promise<Outcome>((resolve) => {
      const cancelTimeout = clock.after(timeoutMs, () => resolve({ failure: TIMEOUT_MESSAGE, throttled: false }))
      const finish = (outcome: Outcome) => {
        cancelTimeout()
        resolve(outcome)
      }
      Promise.resolve()
        .then(work)
        .then(
          () => finish({ failure: null, throttled: false }),
          (error: unknown) => finish({ failure: failureText(error), throttled: isThrottleAnswer(error) }),
        )
    })
  }

  const waitFor = (ms: number): Promise<void> => (ms > 0 ? new Promise((resolve) => clock.after(ms, resolve)) : Promise.resolve())

  async function execute(work: () => Promise<unknown>): Promise<void> {
    const id = ++generation
    const started = clock.now()
    stopTimers()
    set({ status: 'busy', message: '', cooling: false })
    const outcome = await outcomeOf(work)
    await waitFor(MIN_BUSY_MS - (clock.now() - started))
    if (id !== generation) return
    inFlight = null
    if (outcome.failure === null) return finished()
    stopWithFailure(outcome, id)
  }

  /** The end of a run that succeeded: the short success line, then idle again. */
  function finished(): void {
    set(DONE)
    cancelIdle = clock.after(SUCCESS_LINE_MS, () => set(IDLE))
  }

  /** The end of a run that was refused: a throttle keeps the button waiting, anything else frees it at once. */
  function stopWithFailure(outcome: Outcome, id: number): void {
    const message = outcome.failure ?? FAILED_MESSAGE
    if (!outcome.throttled || cooldownMs <= 0) return set({ status: 'failed', message, cooling: false })
    set({ status: 'failed', message, cooling: true })
    cancelCooldown = clock.after(cooldownMs, () => {
      if (id === generation) set(IDLE)
    })
  }

  return {
    view: () => current,
    run(work) {
      if (inFlight) return inFlight
      if (current.cooling) return Promise.resolve()
      inFlight = execute(work)
      return inFlight
    },
    reset() {
      generation += 1
      inFlight = null
      stopTimers()
      set(IDLE)
    },
    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
  }
}
