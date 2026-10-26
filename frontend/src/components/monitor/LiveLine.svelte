<script lang="ts">
  // One quiet row on a machine's card: CPU and memory right now, as the card's own polling handed them in. The row is always there, so the card keeps its
  // shape; before the first reading the two numbers are dashes.
  import { UNKNOWN } from '../../lib/cardFacts.ts'
  import { formatPercent, MEASURING_TEXT, percentOf } from '../../lib/stats.ts'
  import { CARD_ICONS } from '../../lib/machineIcons.ts'
  import Icon from '../Icon.svelte'
  import type { MachineStats } from '../../lib/types.ts'

  let { stats }: { stats: MachineStats | null } = $props()

  const cpu = $derived(stats === null ? UNKNOWN : stats.cpu.total_percent === null ? MEASURING_TEXT : formatPercent(stats.cpu.total_percent))
  const memory = $derived(stats === null ? UNKNOWN : formatPercent(percentOf(stats.memory.used_bytes, stats.memory.total_bytes)))
</script>

<!-- The test id is there only once a reading is: the browser tests wait for the numbers, never for the empty row. -->
<div class="live nums" data-testid={stats === null ? undefined : 'live-line'}>
  <Icon path={CARD_ICONS.cpu} />
  CPU {cpu} · memory {memory}
</div>

<style>
  .live { display: flex; align-items: center; gap: 6px; min-height: 30px; padding: 8px 16px; border-bottom: 1px solid var(--line); font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
