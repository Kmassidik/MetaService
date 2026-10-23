<script lang="ts">
  import type { Snippet } from 'svelte'

  let { open, title, onClose, children, wide = false, closeButton = false, locked = false, backdropClose = false, spacious = false, roomy = false, onReset }: { open: boolean; title: string; onClose: () => void; children: Snippet; wide?: boolean; closeButton?: boolean; locked?: boolean; backdropClose?: boolean; spacious?: boolean; roomy?: boolean; onReset?: (() => void) | undefined } = $props()
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

  /** A click on the dark backdrop (the dialog element itself, not its content) closes a dialog that asked for it, unless a request is running. */
  function closeOnBackdrop(event: MouseEvent) {
    if (backdropClose && !locked && event.target === element) onClose()
  }

  /** The close event arrives a moment after the dialog closes. If the dialog was opened again meanwhile, the event is about the earlier closing and is ignored. */
  function closedByPerson() {
    if (!element?.open) onClose()
  }
</script>

<dialog bind:this={element} onclose={closedByPerson} oncancel={keepWhileLocked} onclick={closeOnBackdrop} class:wide class:spacious class:roomy aria-labelledby="dialog-title">
  <div class="modal-head">
    <h3 id="dialog-title">{title}</h3>
    {#if onReset || closeButton}
      <span class="tools">
        {#if onReset}
          <button class="modal-tool" type="button" aria-label="Reset" title="Reset" disabled={locked} onclick={onReset}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2.4-5.7M4 4v4.5h4.5" /></svg>
          </button>
        {/if}
        {#if closeButton}<button class="modal-x" type="button" aria-label="Close" onclick={onClose}>✕</button>{/if}
      </span>
    {/if}
  </div>
  <div class="modal-body">{@render children()}</div>
</dialog>

<style>
  dialog { max-height: calc(100vh - 32px); overflow-y: auto; width: min(560px, calc(100vw - 32px)); padding: 0; border: 1px solid var(--line-strong); background: var(--surface); color: var(--text); box-shadow: var(--shadow-window); }
  dialog.wide { width: min(1040px, calc(100vw - 32px)); }
  dialog.spacious { width: min(760px, calc(100vw - 32px)); }
  /* A form laid out like Proxmox's windows: two columns of labelled rows on a light grey panel, white boxes on it. */
  dialog.roomy { width: min(900px, calc(100vw - 32px)); }
  dialog::backdrop { background: var(--scrim); }
  .modal-head { padding: 14px 18px; border-bottom: 1px solid var(--line); }
  .modal-head h3 { font-family: var(--mono); font-size: 13px; font-weight: 700; margin: 0; }
  .spacious .modal-head { padding: 20px 24px; }
  .spacious .modal-head h3 { font-size: 17px; letter-spacing: -.01em; }
  .spacious .modal-body { padding: 24px; }
  .roomy .modal-head { padding: 12px 16px 12px 20px; }
  .roomy .modal-head h3 { font-size: 15px; color: var(--accent-d); }
  .roomy .modal-body { padding: 18px 20px 16px; background: var(--surface-2); }
  .modal-body { padding: 20px 22px; display: grid; gap: 14px; }
  .tools { display: inline-flex; align-items: center; gap: 6px; }
  .modal-tool { display: inline-grid; place-items: center; width: 26px; height: 26px; padding: 0; border: 0; border-radius: 50%; background: none; color: var(--accent-d); }
  .modal-tool svg { width: 18px; height: 18px; fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
  .modal-tool:hover { background: var(--surface-2); }
  .modal-tool:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .modal-tool:disabled { opacity: .45; cursor: not-allowed; }
</style>
