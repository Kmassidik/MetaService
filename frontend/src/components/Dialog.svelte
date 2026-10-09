<script>
  let { open, title, onClose, children, wide = false } = $props()
  let element

  $effect(() => {
    if (open && !element.open) element.showModal()
    if (!open && element.open) element.close()
  })
</script>

<dialog bind:this={element} onclose={onClose} class:wide aria-labelledby="dialog-title">
  <div class="modal-head"><h3 id="dialog-title">{title}</h3></div>
  <div class="modal-body">{@render children()}</div>
</dialog>

<style>
  dialog { max-height: calc(100vh - 32px); overflow-y: auto; width: min(560px, calc(100vw - 32px)); padding: 0; border: 1px solid var(--black); background: var(--white); color: var(--black); box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4); }
  dialog.wide { width: min(1040px, calc(100vw - 32px)); }
  dialog::backdrop { background: rgba(17, 17, 17, 0.6); }
  .modal-head { padding: 14px 18px; border-bottom: 1px solid var(--gray); }
  .modal-head h3 { font-family: var(--mono); font-size: 13px; font-weight: 700; margin: 0; }
  .modal-body { padding: 20px 22px; display: grid; gap: 14px; }
</style>
