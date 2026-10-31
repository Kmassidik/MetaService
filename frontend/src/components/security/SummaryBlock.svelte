<script lang="ts">
  // The summary: failed logins and blocked addresses for 24 hours, 7 days and 30 days, and a bar chart of failed logins per day.
  import MetricCard from '../monitor/MetricCard.svelte'
  import DailyBars from './DailyBars.svelte'
  import { numberText, summaryHeadline } from '../../lib/securityRules.ts'
  import type { MachineSecurity, SecurityCount } from '../../lib/types.ts'

  let { report }: { report: MachineSecurity } = $props()
  const groups = $derived<{ label: string; count: SecurityCount }[]>([
    { label: '24 hours', count: report.windows.h24 },
    { label: '7 days', count: report.windows.d7 },
    { label: '30 days', count: report.windows.d30 },
  ])
</script>

<MetricCard label="Summary" hint="Failed logins are tries with a wrong key or password. Blocked addresses are the ones the ban tool shut out after too many tries.">
  <p class="headline">{summaryHeadline(report.windows)}</p>
  <div class="groups">
    {#each groups as group (group.label)}
      <div class="group" data-window={group.label}>
        <span class="when">{group.label}</span>
        <b>{numberText(group.count.failed)}</b><span class="what">failed logins</span>
        <b>{numberText(group.count.blocked)}</b><span class="what">blocked addresses</span>
      </div>
    {/each}
  </div>
  {#if report.daily_failed.length > 0}
    <DailyBars days={report.daily_failed} />
  {:else}
    <p class="note">The helper has not sent the daily numbers yet.</p>
  {/if}
</MetricCard>

<style>
  .headline { margin: 0; font-size: 13px; color: var(--m60); }
  .groups { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
  .group { display: grid; gap: 2px; padding: 10px 12px; border: 1px solid var(--line); min-width: 0; }
  .when { font-family: var(--mono); font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  b { font: 700 18px var(--mono); font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
  .what { font-size: 11px; color: var(--m50); margin-bottom: 4px; }
  .note { margin: 0; font-size: 12px; color: var(--m50); }
  @media (max-width: 480px) { .groups { gap: 6px; } .group { padding: 8px; } b { font-size: 15px; } }
</style>
