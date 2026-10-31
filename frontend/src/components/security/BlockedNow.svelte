<script lang="ts">
  // Blocked now: the addresses a ban tool is keeping out at this moment, across all watched machines. Read only: nothing can be unblocked from here.
  import Pagination from '../Pagination.svelte'
  import { Pager } from '../../lib/pager.svelte.ts'
  import MetricCard from '../monitor/MetricCard.svelte'
  import { relativeTime } from '../../lib/format.ts'
  import { blockEndText, numberText } from '../../lib/securityRules.ts'
  import type { BlockedNowRow } from '../../lib/securityTypes.ts'
  import { nameOf, type MachineInfo } from '../../lib/securityView.ts'

  let { rows, infos, now }: { rows: BlockedNowRow[]; infos: MachineInfo[]; now: number } = $props()
  const pager = new Pager('blocked-now')
  const shown = $derived(pager.slice(rows))
</script>

<MetricCard label="Blocked now" hint="Addresses a ban tool keeps out for a while because they failed to log in too often. Nothing can be unblocked from here.">
  {#if rows.length === 0}
    <p class="none" data-testid="blocked-empty">No address is blocked right now on the machines that are watched.</p>
  {:else}
    <div class="scroll">
      <table class="restable stack" data-testid="security-blocked">
        <thead><tr><th>Address</th><th>Machine</th><th>Since</th><th>Until</th><th class="num">Attempts</th></tr></thead>
        <tbody>
          {#each shown as row (`${row.machine}/${row.address}`)}
            <tr>
              <td data-label="Address" class="addr">{row.address}</td>
              <td data-label="Machine">{nameOf(infos, row.machine)}</td>
              <td data-label="Since" title={row.since ?? ''}>{row.since === null ? '–' : relativeTime(row.since, now)}</td>
              <td data-label="Until" title={row.until ?? ''}>{blockEndText(row.until, now)}</td>
              <td data-label="Attempts" class="nums num">{numberText(row.attempts)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    <Pagination {pager} total={rows.length} label="blocked addresses" />
    </div>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .scroll { overflow-x: auto; }
  .addr { font-family: var(--mono); overflow-wrap: anywhere; }
  .num { text-align: right; }
  :global(.restable.stack td) { padding: 8px 14px; }
  @media (max-width: 820px) { .num { text-align: left; } :global(.restable.stack tbody td) { padding: 3px 6px; } }
</style>
