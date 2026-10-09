<script>
  import Dialog from './Dialog.svelte'

  let { link, onClose } = $props()
</script>

<Dialog open={link !== null} title="Open chat" {onClose}>
  {#if link}
    <p>The link carries the chat's access key after the <code>#</code>, so the key is never sent to any server. Keep the link to yourself.</p>
    <p><a class="btn primary" href={link} target="_blank" rel="noopener noreferrer">Open {link.split('#')[0]}</a></p>
    <div class="done"><button class="btn" type="button" onclick={onClose}>Close</button></div>
  {/if}
</Dialog>

<style>
  .done { display: flex; justify-content: flex-end; }
  code { font-family: var(--mono); }
</style>
