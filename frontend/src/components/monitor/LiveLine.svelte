<script lang="ts">
  // One quiet row on a machine's card: CPU and memory right now. Asks every 15 seconds while the tab is visible, and only for a machine that is
  // awake. The row is always there, so the card keeps its shape; before the first reading the two numbers are dashes.
  import { untrack } from 'svelte'
  import { getMachineStats } from '../../lib/api.ts'
  import { UNKNOWN } from '../../lib/cardFacts.ts'
  import { formatPercent, isStale, LIST_POLL_MS, MEASURING_TEXT, percentOf } from '../../lib/stats.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import { CARD_ICONS } from '../../lib/machineIcons.ts'
  import Icon from '../Icon.svelte'
  import type { MachineStats } from '../../lib/types.ts'

  let { machineId, live = true }: { machineId: string; live?: boolean } = $props()
  let stats = $state<MachineStats | null>(null)

  const cpu = $derived(stats === null ? UNKNOWN : stats.cpu.total_percent === null ? MEASURING_TEXT : formatPercent(stats.cpu.total_percent))
  const memory = $derived(stats === null ? UNKNOWN : formatPercent(percentOf(stats.memory.used_bytes, stats.memory.total_bytes)))

  async function load() {
    try {
      const reply = await getMachineStats(machineId, false)
      stats = isStale(reply) ? null : reply.stats
    } catch {
      stats = null
    }
  }

  $effect(() => {
    if (!live) return
    return untrack(() => startPolling(browserEnvironment(), LIST_POLL_MS, load))
  })
</script>

<!-- The test id is there only once a reading is: the browser tests wait for the numbers, never for the empty row. -->
<div class="live nums" data-testid={stats === null ? undefined : 'live-line'}>
  <Icon path={CARD_ICONS.cpu} />
  CPU {cpu} · memory {memory}
</div>

<style>
  .live { display: flex; align-items: center; gap: 6px; min-height: 30px; padding: 8px 16px; border-bottom: 1px solid var(--line); font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
