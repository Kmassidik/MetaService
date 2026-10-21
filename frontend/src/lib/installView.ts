// What the install view says about a job: how far it is, its title, its steps in words, the elapsed time. Pure.
import type { InstallJob, StepState } from './types.ts'

const SECOND_MS = 1000
const SECONDS_PER_MINUTE = 60

const STEP_WORD: Record<StepState, string> = { pending: 'Waiting', running: 'Running', done: 'Done', failed: 'Failed' }

/** The word for a step state, read by a screen reader next to the mark (the mark's shape is not the only sign either). */
export const stepWord = (state: StepState): string => STEP_WORD[state]

/** How many steps are done, how many there are, and the number (from 1) of the step that is running or failed. */
export function installProgress(job: InstallJob): { done: number; total: number; current: number | null } {
  const active = job.steps.findIndex((step) => step.state === 'running' || step.state === 'failed')
  return { done: job.steps.filter((step) => step.state === 'done').length, total: job.steps.length, current: active < 0 ? null : active + 1 }
}

export function installTitle(job: InstallJob): string {
  if (job.state === 'done') return `${job.name} is online`
  if (job.state === 'running') return `Installing ${job.name}`
  const { current } = installProgress(job)
  return current === null ? 'The install stopped' : `Stopped at step ${current}`
}

/** Minutes and seconds, like 2:31. */
export function formatElapsed(milliseconds: number): string {
  const seconds = Math.floor(Math.max(0, milliseconds) / SECOND_MS)
  const rest = seconds % SECONDS_PER_MINUTE
  return `${Math.floor(seconds / SECONDS_PER_MINUTE)}:${String(rest).padStart(2, '0')}`
}
