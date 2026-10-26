// The action state machine (action.ts) as something a Svelte page can read: `status`, `message` and `cooling` update the screen by themselves.
import { createAction, type ActionOptions, type ActionStatus, type ActionView } from './action.ts'

export class ActionState {
  status = $state<ActionStatus>('idle')
  message = $state('')
  cooling = $state(false)
  readonly #action: ReturnType<typeof createAction>

  constructor(options: ActionOptions = {}) {
    this.#action = createAction(options)
    this.#action.subscribe((view) => {
      this.status = view.status
      this.message = view.message
      this.cooling = view.cooling
    })
  }

  get busy(): boolean {
    return this.status === 'busy'
  }

  /** What the helpers of action.ts read: the same view, with no listener of its own. */
  get view(): ActionView {
    return { status: this.status, message: this.message, cooling: this.cooling }
  }

  /** Runs the work once; a call while it runs or while a throttle cooldown lasts does nothing. Never throws: a failure becomes `message`. */
  run = (work: () => Promise<unknown>): Promise<void> => this.#action.run(work)

  /** Forgets the last answer and frees the button, for a dialog that is opened again. */
  reset = (): void => this.#action.reset()
}
