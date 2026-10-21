// Asks for something again and again, only while the tab is visible. Hidden: no timer. Visible again: ask at once, then keep going.

export interface PollEnvironment {
  isVisible: () => boolean
  onVisibilityChange: (listener: () => void) => () => void
  setTimer: (run: () => void, ms: number) => number
  clearTimer: (timer: number) => void
}

/** The real browser. */
export function browserEnvironment(): PollEnvironment {
  return {
    isVisible: () => document.visibilityState === 'visible',
    onVisibilityChange: (listener) => {
      document.addEventListener('visibilitychange', listener)
      return () => document.removeEventListener('visibilitychange', listener)
    },
    setTimer: (run, ms) => window.setTimeout(run, ms),
    clearTimer: (timer) => window.clearTimeout(timer),
  }
}

/**
 * Runs `load` now (when visible) and then `intervalMs` after each run ends, so two runs never overlap.
 * Returns the function that stops it for good.
 */
export function startPolling(environment: PollEnvironment, intervalMs: number, load: () => Promise<void>): () => void {
  let timer: number | null = null
  let running = false
  let stopped = false

  const clear = () => {
    if (timer === null) return
    environment.clearTimer(timer)
    timer = null
  }

  const schedule = () => {
    clear()
    if (stopped || !environment.isVisible()) return
    timer = environment.setTimer(tick, intervalMs)
  }

  async function tick() {
    timer = null
    if (stopped || running || !environment.isVisible()) return
    running = true
    try {
      await load()
    } finally {
      running = false
      schedule()
    }
  }

  const stopListening = environment.onVisibilityChange(() => {
    if (environment.isVisible()) void tick()
    else clear()
  })
  void tick()

  return () => {
    stopped = true
    clear()
    stopListening()
  }
}
