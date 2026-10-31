// What the Security page keeps while it is open: the overview, the loaded rows of the log with the cursor of the next page, and for each of the two whether it is
// loading, ready, missing (the parent has no security API) or failed. An answer that arrives after the person asked for something else is dropped.
import { ApiError } from './api.ts'
import { loadSource, type LoadedSource } from './securitySource.ts'
import { MAX_LOADED_EVENTS, type EventQuery, type SecurityEvent, type SecurityOverview, type SecurityRange } from './securityTypes.ts'
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
  next = $state<string | null>(null)
  eventsPhase = $state<Phase>('loading')
  eventsError = $state('')
  loadingMore = $state(false)
  /** The sample's own machines in preview; null when the panel's machines are listed. */
  sampleMachines = $state<MachineInfo[] | null>(null)

  #loaded: { preview: boolean; value: LoadedSource } | null = null
  #overviewAsk = 0
  #eventsAsk = 0

  /** True when the log holds as many rows as it may; the person is told to narrow the filters. */
  readonly full = $derived(this.events.length >= MAX_LOADED_EVENTS)

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

  async loadEvents(preview: boolean, query: EventQuery): Promise<void> {
    const ask = ++this.#eventsAsk
    this.eventsPhase = 'loading'
    this.events = []
    this.next = null
    this.eventsError = ''
    try {
      const page = await (await this.#source(preview)).source.events(query)
      if (ask !== this.#eventsAsk) return
      this.events = page?.events ?? []
      this.next = page?.next_cursor ?? null
      this.eventsPhase = page === null ? 'missing' : 'ready'
    } catch (error) {
      if (ask !== this.#eventsAsk) return
      this.eventsError = failureText(error)
      this.eventsPhase = 'error'
    }
  }

  /** The next page of the log, added below the rows already shown. */
  async loadMore(preview: boolean, query: EventQuery): Promise<void> {
    if (this.next === null || this.loadingMore || this.full) return
    const ask = ++this.#eventsAsk
    this.loadingMore = true
    this.eventsError = ''
    try {
      const page = await (await this.#source(preview)).source.events({ ...query, cursor: this.next })
      if (ask !== this.#eventsAsk) return
      this.events = [...this.events, ...(page?.events ?? [])].slice(0, MAX_LOADED_EVENTS)
      this.next = page?.next_cursor ?? null
    } catch (error) {
      if (ask === this.#eventsAsk) this.eventsError = failureText(error)
    } finally {
      this.loadingMore = false
    }
  }
}
