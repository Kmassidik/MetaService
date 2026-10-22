<script lang="ts">
  import type { Snippet } from 'svelte'

  let { open, title, onClose, children, wide = false, closeButton = false, locked = false }: { open: boolean; title: string; onClose: () => void; children: Snippet; wide?: boolean; closeButton?: boolean; locked?: boolean } = $props()
  let element: HTMLDialogElement | undefined

  $effect(() => {
    const dialog = element
    if (!dialog) return
    if (open && !dialog.open) dialog.showModal()
    if (!open && dialog.open) dialog.close()
  })

  /** Escape asks the dialog to close; while a request is running the dialog stays (it closes itself when the request ends). */
  function keepWhileLocked(event: Event) {
    if (locked) event.preventDefault()
  }

  /** The close event arrives a moment after the dialog closes. If the dialog was opened again meanwhile, the event is about the earlier closing and is ignored. */
  function closedByPerson() {
    if (!element?.open) onClose()
  }
</script>

<dialog bind:this={element} onclose={closedByPerson} oncancel={keepWhileLocked} class:wide aria-labelledby="dialog-title">
  <div class="modal-head">
    <h3 id="dialog-title">{title}</h3>
    {#if closeButton}<button class="modal-x" type="button" aria-label="Close" onclick={onClose}>✕</button>{/if}
  </div>
  <div class="modal-body">{@render children()}</div>
</dialog>

<style>
  dialog { max-height: calc(100vh - 32px); overflow-y: auto; width: min(560px, calc(100vw - 32px)); padding: 0; border: 1px solid var(--line-strong); background: var(--surface); color: var(--text); box-shadow: var(--shadow-window); }
  dialog.wide { width: min(1040px, calc(100vw - 32px)); }
  dialog::backdrop { background: var(--scrim); }
  .modal-head { padding: 14px 18px; border-bottom: 1px solid var(--line); }
  .modal-head h3 { font-family: var(--mono); font-size: 13px; font-weight: 700; margin: 0; }
  .modal-body { padding: 20px 22px; display: grid; gap: 14px; }
</style>
