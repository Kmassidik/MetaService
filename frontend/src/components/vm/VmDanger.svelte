<script lang="ts">
  // The Danger tab, in the MAAS words. The click opens the confirm dialog; the accepted order then keeps Delete busy. On an offline machine Delete is off, with the reason beside it.
  import ActionLine from '../ActionLine.svelte'
  import { MACHINE_OFFLINE_REASON } from '../../lib/machineOffline.ts'

  let { onDelete, deleting, offline }: { onDelete: () => void; deleting: boolean; offline: boolean } = $props()
</script>

<p class="hint">Deleting destroys the VM and its disk permanently — this can't be undone.</p>
<div class="actions">
  <button class="btn danger" type="button" disabled={deleting || offline} title={offline ? MACHINE_OFFLINE_REASON : undefined} aria-busy={deleting} onclick={onDelete}>{#if deleting}<span class="btn-spin" aria-hidden="true"></span>Deleting…{:else}Delete instance{/if}</button>
  <ActionLine line={offline ? MACHINE_OFFLINE_REASON : ''} failed={false} />
</div>

<style>
  .hint { font-size: 13px; color: var(--m60); line-height: 1.6; margin: 0 0 8px; }
  .actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
</style>
