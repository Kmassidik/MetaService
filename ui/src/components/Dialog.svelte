<script>
  let { open, title, onClose, children } = $props()
  let element

  $effect(() => {
    if (open && !element.open) element.showModal()
    if (!open && element.open) element.close()
  })
</script>

<dialog bind:this={element} onclose={onClose} aria-labelledby="dialog-title">
  <div class="body">
    <h2 id="dialog-title">{title}</h2>
    {@render children()}
  </div>
</dialog>

<style>
  dialog {
    width: min(480px, calc(100vw - 32px));
    padding: 0;
    border: 1px solid var(--line);
    border-radius: 14px;
    background: var(--surface);
    color: var(--ink);
    box-shadow: var(--shadow);
  }
  dialog::backdrop { background: rgb(8 12 20 / 55%); }
  .body { display: grid; gap: 14px; padding: 24px; }
  h2 { font-size: 20px; }
</style>
