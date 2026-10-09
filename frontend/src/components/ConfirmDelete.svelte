<script>
  import Dialog from './Dialog.svelte'

  let { target, busy, failure, onCancel, onConfirm } = $props()
</script>

<Dialog open={target !== null} title="Delete this workload?" onClose={onCancel}>
  {#if target}
    <p><strong>{target.workload.name}</strong> on <strong>{target.machine.name}</strong> will be stopped and deleted. The machine makes a backup of it first and keeps that backup;
      if the backup fails, nothing is deleted.</p>
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="row">
      <button class="btn line" type="button" onclick={onCancel}>Keep it</button>
      <button class="btn danger" type="button" disabled={busy} onclick={onConfirm}>{busy ? 'Asking…' : 'Back up and delete'}</button>
    </div>
  {/if}
</Dialog>

<style>
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
  .bad { color: var(--danger); }
</style>
