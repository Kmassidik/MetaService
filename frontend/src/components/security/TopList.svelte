<script lang="ts">
  // The top rows of one list (user names the bots try, or addresses attacking most), each with its count and a small bar relative to the biggest.
  import MetricCard from '../monitor/MetricCard.svelte'
  import { numberText } from '../../lib/securityRules.ts'
  import type { TopRow } from '../../lib/securityTypes.ts'
  import { topShares, topShown } from '../../lib/securityView.ts'

  let { label, hint, rows, testId }: { label: string; hint: string; rows: TopRow[]; testId: string } = $props()
  const shown = $derived(topShown(rows))
  const shares = $derived(topShares(shown))
</script>

<MetricCard {label} {hint}>
  {#if shown.length === 0}
    <p class="none">Nothing counted in this time range.</p>
  {:else}
    <ol data-testid={testId}>
      {#each shown as row, index (row.name)}
        <li>
          <span class="name">{row.name}</span>
          <span class="nums count">{numberText(row.count)}</span>
          <span class="bar" aria-hidden="true"><i style:width="{(shares[index] ?? 0) * 100}%"></i></span>
        </li>
      {/each}
    </ol>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  ol { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  li { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 2px 10px; font-size: 13px; }
  .name { font-family: var(--mono); font-size: 12px; overflow-wrap: anywhere; }
  .count { color: var(--m60); font-family: var(--mono); font-size: 12px; }
  .bar { grid-column: 1 / -1; height: 4px; background: var(--line); display: block; }
  .bar i { display: block; height: 100%; background: var(--chart-orange); }
</style>
