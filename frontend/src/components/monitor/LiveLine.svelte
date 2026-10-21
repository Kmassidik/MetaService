<script lang="ts">
  // One quiet line on a machine's card: CPU and memory right now. Asks every 15 seconds while the tab is visible. Nothing is shown until a reading arrives.
  import { untrack } from 'svelte'
  import { getMachineStats } from '../../lib/api.ts'
  import { formatPercent, isStale, LIST_POLL_MS, MEASURING_TEXT, percentOf } from '../../lib/stats.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import type { MachineStats } from '../../lib/types.ts'

  let { machineId }: { machineId: string } = $props()
  let stats = $state<MachineStats | null>(null)

  async function load() {
    try {
      const reply = await getMachineStats(machineId)
      stats = isStale(reply) ? null : reply.stats
    } catch {
      stats = null
    }
  }

  $effect(() => untrack(() => startPolling(browserEnvironment(), LIST_POLL_MS, load)))
</script>

{#if stats}
  <div class="live nums" data-testid="live-line">
    CPU {stats.cpu.total_percent === null ? MEASURING_TEXT : formatPercent(stats.cpu.total_percent)} · memory {formatPercent(percentOf(stats.memory.used_bytes, stats.memory.total_bytes))}
  </div>
{/if}

<style>
  .live { padding: 8px 16px; border-bottom: 1px solid var(--gray); font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
