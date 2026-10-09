<script>
  import Dialog from './Dialog.svelte'

  let { machine, busy, failure, onCancel, onConfirm } = $props()
</script>

<Dialog open={machine !== null} title="Remove this machine?" onClose={onCancel}>
  {#if machine}
    <p><strong>{machine.name}</strong> will disappear from MetaService and its token stops working. Its VMs keep running on the machine.
      To manage it again it must enroll with a new token.</p>
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="row">
      <button class="btn line" type="button" onclick={onCancel}>Keep it</button>
      <button class="btn danger" type="button" disabled={busy} onclick={onConfirm}>{busy ? 'Removing…' : 'Remove machine'}</button>
    </div>
  {/if}
</Dialog>

<style>
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
  .bad { color: var(--danger); }
</style>
