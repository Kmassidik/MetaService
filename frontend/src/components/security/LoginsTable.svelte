<script lang="ts">
  // Successful logins by method, user and address. The machines should be key-only, so a password login is marked as a warning and listed first.
  import MetricCard from '../monitor/MetricCard.svelte'
  import { numberText, orderLogins } from '../../lib/securityRules.ts'
  import { relativeTime } from '../../lib/format.ts'
  import type { MachineSecurity } from '../../lib/types.ts'

  let { report, now }: { report: MachineSecurity; now: number } = $props()
  const rows = $derived(orderLogins(report.logins))
</script>

<MetricCard label="Successful logins" hint="Who really got in. These machines should only accept keys, so a login with a password is marked and listed first.">
  {#if rows.length === 0}
    <p class="none">No successful logins were reported.</p>
  {:else}
    <div class="scroll">
      <table class="restable stack">
        <thead><tr><th>Method</th><th>User</th><th>Address</th><th>Times</th><th>Last seen</th></tr></thead>
        <tbody>
          {#each rows as row (`${row.method}|${row.user}|${row.address}`)}
            <tr class:bad={row.method === 'password'} data-method={row.method}>
              <td data-label="Method"><span class="tag" class:warn={row.method === 'password'} class:run={row.method === 'key'}>{row.method === 'key' ? 'Key' : 'Password'}</span></td>
              <td data-label="User" class="mono">{row.user}</td>
              <td data-label="Address" class="mono">{row.address}</td>
              <td data-label="Times" class="nums">{numberText(row.count)}</td>
              <td data-label="Last seen" title={row.last_seen ?? ''}>{row.last_seen === null ? '–' : relativeTime(row.last_seen, now)}</td>
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
  .mono { font-family: var(--mono); overflow-wrap: anywhere; }
  tr.bad { background: var(--warn-note-bg); }
  :global(.restable.stack td) { padding: 10px 14px; }
  @media (max-width: 820px) { :global(.restable.stack tbody td) { padding: 3px 0; } }
</style>
