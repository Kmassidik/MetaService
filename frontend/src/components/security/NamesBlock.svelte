<script lang="ts">
  // Names the bots try: the eight user names that failed to log in most, as plain text with a small bar each. The names come from attackers,
  // so they are only ever put in as text (never as markup).
  import MetricCard from '../monitor/MetricCard.svelte'
  import { nameShares, numberText, topNames } from '../../lib/securityRules.ts'
  import type { MachineSecurity } from '../../lib/types.ts'

  const PERCENT = 100

  let { report }: { report: MachineSecurity } = $props()
  const rows = $derived(topNames(report.usernames))
  const shares = $derived(nameShares(rows))
</script>

<MetricCard label="Names the bots try" hint="The user names that automatic guessers tried most often. They are guesses, not people. None of them is a real account unless you made it.">
  {#if rows.length === 0}
    <p class="none">No failed user names were reported.</p>
  {:else}
    <ul>
      {#each rows as row, index (row.name)}
        <li>
          <span class="name">{row.name}</span>
          <span class="bar" aria-hidden="true"><i style:width="{(shares[index] ?? 0) * PERCENT}%"></i></span>
          <span class="n nums">{numberText(row.count)}</span>
        </li>
      {/each}
    </ul>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  li { display: grid; grid-template-columns: minmax(70px, 140px) minmax(0, 1fr) auto; gap: 10px; align-items: center; font-size: 13px; }
  .name { font-family: var(--mono); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar { display: block; height: 8px; background: var(--surface-2); }
  .bar i { display: block; height: 100%; background: var(--chart-orange); }
  .n { font-family: var(--mono); font-size: 12px; min-width: 6ch; text-align: right; }
</style>
