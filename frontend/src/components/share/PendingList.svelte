<script lang="ts">
  import PendingRow from './PendingRow.svelte'
  import type { PendingMachine } from '../../lib/share.ts'

  let { machines, now, onChanged }: { machines: PendingMachine[]; now: number; onChanged: () => Promise<void> } = $props()
</script>

{#if machines.length === 0}
  <p class="none" data-testid="pending-empty">Nobody is waiting. When a far PC runs the command, it shows up here.</p>
{:else}
  <div class="tablewrap" role="region" aria-label="Waiting machines, scroll to view columns">
    <table class="restable stack">
      <thead><tr><th>Machine</th><th>Share (you can lower it)</th><th>Code from its screen</th><th><span class="sr">Actions</span></th></tr></thead>
      <tbody>
        {#each machines as machine (machine.id)}
          <PendingRow {machine} {now} {onChanged} />
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<style>
  .none { margin: 0; padding: 16px 28px; color: var(--m50); font-size: 13px; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
  @media (max-width: 820px) { .none { padding: 16px; } }
</style>
