<script lang="ts">
  // Recent activity: the last calls of the AI clients. Token names and targets are text only.
  import type { ActivityRow } from '../../lib/mcpRequests.ts'
  import { agoText } from '../../lib/mcpText.ts'

  let { rows, now }: { rows: ActivityRow[]; now: number } = $props()
</script>

{#if rows.length === 0}
  <p class="none" data-testid="mcp-activity-empty">No calls yet. Every call an AI client makes is listed here.</p>
{:else}
  <div class="tablewrap">
    <table class="restable stack" data-testid="mcp-activity">
      <thead><tr><th>When</th><th>Token</th><th>Tool</th><th>Target</th><th>Result</th></tr></thead>
      <tbody>
        {#each rows as row, index (index)}
          <tr>
            <td data-label="When">{agoText(row.at, now)}</td>
            <td class="c-name" data-label="Token">{row.tokenName}</td>
            <td class="mono" data-label="Tool">{row.tool}</td>
            <td class="small" data-label="Target">{row.target ?? '—'}</td>
            <td data-label="Result">{row.status}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<style>
  .none { margin: 0; color: var(--m50); font-size: 13px; }
  .tablewrap { padding: 0; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m50); overflow-wrap: anywhere; }
</style>
