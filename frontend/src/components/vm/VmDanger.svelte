<script lang="ts">
  // The Danger tab, in the MAAS words. The click opens the confirm dialog; the delete itself waits for that answer.
  let { onDelete }: { onDelete: () => void } = $props()
</script>

<p class="hint">Deleting destroys the VM and its disk permanently — this can't be undone.</p>
<button class="btn danger" type="button" onclick={onDelete}>Delete instance</button>

<style>
  .hint { font-size: 13px; color: var(--m60); line-height: 1.6; margin: 0 0 8px; }
</style>
