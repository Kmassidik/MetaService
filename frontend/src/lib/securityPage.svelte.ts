// What the Security page keeps while it is open: the overview, the rows of the page of the log being shown with the count of all matching rows, and for each of the two whether it is
// loading, ready, missing (the parent has no security API) or failed. An answer that arrives after the person asked for something else is dropped.
import { ApiError } from './api.ts'
import { loadSource, type LoadedSource } from './securitySource.ts'
import { type EventQuery, type SecurityEvent, type SecurityOverview, type SecurityRange } from './securityTypes.ts'
import type { MachineInfo } from './securityView.ts'
import { UnreadableAnswer } from './unreadable.ts'

export type Phase = 'loading' | 'ready' | 'missing' | 'error'

const FAILED_PREFIX = 'Security data could not be loaded. '
const UNREADABLE_LINE = 'The answer was not in the shape the panel expects.'

function failureText(error: unknown): string {
  if (error instanceof ApiError || error instanceof UnreadableAnswer) return `${FAILED_PREFIX}${error instanceof ApiError ? error.message : UNREADABLE_LINE}`
  throw error
}

export class SecurityPageData {
  overview = $state<SecurityOverview | null>(null)
  overviewPhase = $state<Phase>('loading')
  overviewError = $state('')
  events = $state<SecurityEvent[]>([])
  /** Every row that matches the filters (not only this page); 0 until the first answer. */
  total = $state(0)
  eventsPhase = $state<Phase>('loading')
  eventsError = $state('')
  /** True while another page or filter is being fetched; the rows already shown stay until the new ones arrive. */
  refreshing = $state(false)
  /** The sample's own machines in preview; null when the panel's machines are listed. */
  sampleMachines = $state<MachineInfo[] | null>(null)

  #loaded: { preview: boolean; value: LoadedSource } | null = null
  #overviewAsk = 0
  #eventsAsk = 0

  async #source(preview: boolean): Promise<LoadedSource> {
    if (this.#loaded?.preview !== preview) {
      this.#loaded = { preview, value: await loadSource(preview, Date.now()) }
      this.sampleMachines = this.#loaded.value.machines
    }
    return this.#loaded.value
  }

  async loadOverview(preview: boolean, range: SecurityRange): Promise<void> {
    const ask = ++this.#overviewAsk
    this.overviewPhase = 'loading'
    this.overview = null
    try {
      const answer = await (await this.#source(preview)).source.overview(range)
      if (ask !== this.#overviewAsk) return
      this.overview = answer
      this.overviewPhase = answer === null ? 'missing' : 'ready'
    } catch (error) {
      if (ask !== this.#overviewAsk) return
      this.overviewError = failureText(error)
      this.overviewPhase = 'error'
    }
  }

  /** One page of the log. The rows of the page before stay on screen until this one arrives (a page change is not a blank screen). */
  async loadEvents(preview: boolean, query: EventQuery): Promise<void> {
    const ask = ++this.#eventsAsk
    this.refreshing = true
    if (this.eventsPhase !== 'ready') this.eventsPhase = 'loading'
    this.eventsError = ''
    try {
      const page = await (await this.#source(preview)).source.events(query)
      if (ask !== this.#eventsAsk) return
      this.events = page?.events ?? []
      this.total = page?.total ?? 0
      this.eventsPhase = page === null ? 'missing' : 'ready'
    } catch (error) {
      if (ask !== this.#eventsAsk) return
      this.eventsError = failureText(error)
      this.eventsPhase = 'error'
    } finally {
      if (ask === this.#eventsAsk) this.refreshing = false
    }
  }
}
