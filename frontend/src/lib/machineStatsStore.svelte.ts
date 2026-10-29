// The machine's real reading (memory, GPU) as something the Compute tab can read. It is read again every few seconds while the tab is open.
import { getMachineStats } from './api.ts'
import type { MachineStats } from './types.ts'

const REFRESH_MS = 15_000

export class MachineStatsStore {
  stats = $state<MachineStats | null>(null)
  failure = $state('')

  /** Reads now and then every REFRESH_MS; the returned function stops it. */
  watch(machineId: string): () => void {
    let active = true
    this.stats = null
    this.failure = ''
    const load = async (): Promise<void> => {
      try {
        const reply = await getMachineStats(machineId, false)
        if (!active) return
        this.stats = reply.stats
        this.failure = reply.stats ? '' : 'No real memory reading is available.'
      } catch (error) {
        if (!active) return
        this.failure = error instanceof Error ? error.message : 'The real memory reading failed.'
      }
    }
    void load()
    const timer = setInterval(() => void load(), REFRESH_MS)
    return () => {
      active = false
      clearInterval(timer)
    }
  }
}
