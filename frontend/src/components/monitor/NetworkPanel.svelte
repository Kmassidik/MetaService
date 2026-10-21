<script lang="ts">
  import MetricCard from './MetricCard.svelte'
  import Sparkline from './Sparkline.svelte'
  import { ceilingOf, formatBytes, formatRate } from '../../lib/stats.ts'
  import type { StatsNetwork } from '../../lib/types.ts'

  const QUIET_BYTES_PER_SECOND = 10 * 1024
  let { network, down, up }: { network: StatsNetwork; down: readonly (number | null)[]; up: readonly (number | null)[] } = $props()
  const ceiling = $derived(ceilingOf([...down, ...up], QUIET_BYTES_PER_SECOND))
</script>

<MetricCard label="Network">
  <dl class="rates">
    <div><dt>Down</dt><dd class="nums" data-testid="net-down">{formatRate(network.received_bytes_per_second)}</dd></div>
    <div><dt>Up</dt><dd class="nums" data-testid="net-up">{formatRate(network.sent_bytes_per_second)}</dd></div>
  </dl>
  <p class="sub nums">Since start: {formatBytes(network.received_total_bytes)} in · {formatBytes(network.sent_total_bytes)} out</p>
  {#snippet graph()}
    <Sparkline values={down} {ceiling} label="Download speed over the last minutes" />
    <Sparkline values={up} {ceiling} label="Upload speed over the last minutes" />
  {/snippet}
</MetricCard>

<style>
  .rates { margin: 0; display: grid; gap: 2px; }
  .rates > div { display: flex; justify-content: space-between; font-family: var(--mono); font-size: 13px; }
  .rates dt { color: var(--m60); }
  .rates dd { margin: 0; font-weight: 700; }
  .sub { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
