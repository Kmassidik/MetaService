// The action state machine (action.ts) as something a Svelte page can read: `status` and `message` update the screen by themselves.
import { createAction, type ActionOptions, type ActionStatus } from './action.ts'

export class ActionState {
  status = $state<ActionStatus>('idle')
  message = $state('')
  readonly #action: ReturnType<typeof createAction>

  constructor(options: ActionOptions = {}) {
    this.#action = createAction(options)
    this.#action.subscribe((view) => {
      this.status = view.status
      this.message = view.message
    })
  }

  get busy(): boolean {
    return this.status === 'busy'
  }

  /** Runs the work once; a call while it is running does nothing. Never throws: a failure becomes `message`. */
  run = (work: () => Promise<unknown>): Promise<void> => this.#action.run(work)
}
