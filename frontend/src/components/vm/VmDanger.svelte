<script lang="ts">
  // The Danger tab, in the MAAS words. The click opens the confirm dialog; the accepted order then keeps Delete busy.
  import ActionLine from '../ActionLine.svelte'

  let { onDelete, deleting, error }: { onDelete: () => void; deleting: boolean; error: string | null } = $props()
</script>

<p class="hint">Deleting destroys the VM and its disk permanently — this can't be undone.</p>
<div class="actions">
  <button class="btn danger" type="button" disabled={deleting} aria-busy={deleting} onclick={onDelete}>{#if deleting}<span class="btn-spin" aria-hidden="true"></span>Deleting…{:else}Delete instance{/if}</button>
  <ActionLine line={error ?? ''} failed={error !== null} />
</div>

<style>
  .hint { font-size: 13px; color: var(--m60); line-height: 1.6; margin: 0 0 8px; }
  .actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
</style>
