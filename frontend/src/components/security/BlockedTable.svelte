<script lang="ts">
  // Blocked now: the addresses the ban tool has shut out, newest first. Read only. The empty state says whether nobody is blocked or nothing can block.
  import MetricCard from '../monitor/MetricCard.svelte'
  import { blockEndText, blockedEmptyText, numberText, orderBlocked } from '../../lib/securityRules.ts'
  import { relativeTime } from '../../lib/format.ts'
  import type { MachineSecurity } from '../../lib/types.ts'

  let { report, now }: { report: MachineSecurity; now: number } = $props()
  const rows = $derived(orderBlocked(report.blocked))

  /** A date the person can read: how long ago, with the exact time in the hover text. */
  const ago = (iso: string | null) => (iso === null ? '–' : relativeTime(iso, now))
</script>

<MetricCard label="Blocked now" hint="Addresses the ban tool keeps out for a while because they failed to log in too often. Nothing can be unblocked from here.">
  {#if rows.length === 0}
    <p class="none" data-testid="blocked-empty">{blockedEmptyText(report)}</p>
  {:else}
    <div class="scroll">
      <table class="restable stack">
        <thead><tr><th>Address</th><th>Blocked since</th><th>Blocked until</th><th>Attempts</th></tr></thead>
        <tbody>
          {#each rows as row (row.address)}
            <tr>
              <td data-label="Address" class="addr">{row.address}</td>
              <td data-label="Since" title={row.since ?? ''}>{ago(row.since)}</td>
              <td data-label="Until" title={row.until ?? ''}>{blockEndText(row.until, now)}</td>
              <td data-label="Attempts" class="nums">{numberText(row.attempts)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .scroll { overflow-x: auto; }
  .addr { font-family: var(--mono); overflow-wrap: anywhere; }
  :global(.restable.stack td) { padding: 10px 14px; }
  @media (max-width: 820px) { :global(.restable.stack tbody td) { padding: 3px 0; } }
</style>
