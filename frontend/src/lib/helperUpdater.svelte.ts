// One "Update helper" run for one machine: whether it is running and the sentence it ended with. Each machine card and the Environment tab hold their own,
// so two machines can update at once without touching each other.
import { ApiError, updateHelper } from './api.ts'
import { failureView, outcomeView, type OutcomeView } from './helperUpdate.ts'

const GENERIC_FAILURE = 'Something went wrong.'

export class HelperUpdater {
  updating = $state(false)
  outcome: OutcomeView | null = $state(null)

  /** Asks the parent to replace the helper of this machine. The answer is told in words, never thrown; a press while it runs does nothing. */
  run = async (machineId: string): Promise<void> => {
    if (this.updating) return
    this.updating = true
    this.outcome = null
    try {
      this.outcome = outcomeView(await updateHelper(machineId))
    } catch (error) {
      this.outcome = error instanceof ApiError ? failureView(error.code, error.message) : failureView('error', GENERIC_FAILURE)
    } finally {
      this.updating = false
    }
  }
}
