// The external services of one machine (Docker, Incus, Apple) as something the page can read: the Building draws them as blocks, the
// table and cards views list them, and both ask for the same read and the same Start / Stop / Restart.
import { ApiError, externalServiceAction, getCommand, listExternalServices } from './api.ts'
import type { Command, ExternalService, ExternalServiceAction, ExternalServicesReply } from './types.ts'

const COMMAND_POLL_MS = 250
const COMMAND_TIMEOUT_MS = 120_000

async function waitForCommand(accepted: Command): Promise<void> {
  let current = accepted
  const deadline = Date.now() + COMMAND_TIMEOUT_MS
  while (current.state !== 'succeeded' && current.state !== 'failed') {
    if (Date.now() >= deadline) throw new ApiError(0, 'timeout', 'The machine is still working. Check the service again shortly.')
    await new Promise<void>((resolve) => setTimeout(resolve, COMMAND_POLL_MS))
    current = await getCommand(accepted.id)
  }
  if (current.state === 'failed') throw new ApiError(0, 'command_failed', current.result?.error ?? 'The machine could not change the service.')
}

export class ExternalServicesStore {
  reply = $state<ExternalServicesReply | null>(null)
  loading = $state(true)
  /** An old helper answers 404: only the external part is hidden, the rest of the machine stays. */
  legacy = $state(false)
  failure = $state('')
  #machineId = ''
  #asked = 0

  get services(): ExternalService[] {
    return this.reply?.services ?? []
  }

  get running(): number {
    return this.services.filter((service) => service.state === 'running').length
  }

  /** Reads this machine's services now; the returned function stops anything still on its way for it. */
  watch(machineId: string): () => void {
    this.#machineId = machineId
    this.reply = null
    this.legacy = false
    this.failure = ''
    void this.#load(machineId, true)
    return () => {
      this.#asked += 1
    }
  }

  /** Only the newest read may update the machine. A 404 means an old helper. */
  async #load(id: string, initial = false): Promise<void> {
    const turn = ++this.#asked
    if (initial) this.loading = true
    try {
      const next = await listExternalServices(id)
      if (turn !== this.#asked) return
      this.reply = next
      this.legacy = false
      this.failure = ''
    } catch (error) {
      if (turn !== this.#asked) return
      if (error instanceof ApiError && error.status === 404) {
        this.reply = null
        this.legacy = true
        this.failure = ''
        return
      }
      this.failure = error instanceof Error ? error.message : 'Something went wrong.'
      if (!initial) throw error
    } finally {
      if (turn === this.#asked) this.loading = false
    }
  }

  /** Starts, stops or restarts one service, waits for the machine to finish, then reads the list again. A failure is thrown for the button to show. */
  run = async (service: ExternalService, action: ExternalServiceAction): Promise<void> => {
    const id = this.#machineId
    const accepted = await externalServiceAction(id, service.id, action)
    await waitForCommand(accepted.command)
    if (id !== this.#machineId) return
    await this.#load(id)
  }
}
