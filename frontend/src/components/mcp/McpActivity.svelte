<script lang="ts">
  // Recent activity: the last calls of the AI clients. Person names and targets are text only.
  import type { ActivityRow } from '../../lib/mcpActivity.ts'
  import { agoText } from '../../lib/mcpText.ts'

  let { rows, now, limit }: { rows: ActivityRow[]; now: number; limit: number } = $props()
</script>

{#if rows.length === 0}
  <p class="none" data-testid="mcp-activity-empty">No calls yet. Every call an AI client makes is listed here.</p>
{:else}
  <p class="none window" data-testid="mcp-activity-window">The last {limit} calls. Older ones are not listed here.</p>
  <div class="tablewrap">
    <table class="restable stack" data-testid="mcp-activity">
      <thead><tr><th>When</th><th>Person</th><th>Tool</th><th>Target</th><th>Result</th></tr></thead>
      <tbody>
        {#each rows as row, index (index)}
          <tr>
            <td data-label="When">{agoText(row.at, now)}</td>
            <td class="c-name" data-label="Person">{row.person}</td>
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
