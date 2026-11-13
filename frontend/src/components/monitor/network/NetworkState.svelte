<script lang="ts">
  // One line under a Network card that says what is there: loading, could not load (with Retry), no readings yet, or that the last numbers are kept after a failed update.
  // It shows nothing once the numbers are there.
  import type { PanelStatus } from '../../../lib/netStatus.ts'

  let { status, onRetry }: { status: PanelStatus; onRetry: () => void } = $props()
  const TEXT: Record<PanelStatus, string> = {
    loading: 'Loading…',
    failed: 'Could not load.',
    empty: 'No readings yet',
    stale: 'Could not update. Showing the last numbers.',
    ready: '',
  }
  const offersRetry = $derived(status === 'failed' || status === 'stale')
</script>

{#if status !== 'ready'}
  <p class="state" role="status">
    {TEXT[status]}
    {#if offersRetry}<button type="button" class="btn line sm" onclick={onRetry}>Retry</button>{/if}
  </p>
{/if}

<style>
  .state { margin: 0; display: flex; align-items: center; flex-wrap: wrap; gap: 8px; font-family: var(--mono); font-size: 12px; color: var(--m60); }
</style>
