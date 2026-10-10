<script>
  /**
   * The full-screen overlay every file view shares: dark backdrop, file name, Download and close
   * (X, Esc, or a tap on the backdrop). Moved to <body> so it covers the side panel on any screen,
   * and Esc closes only the viewer, never the panel behind it.
   * `variant="document"` puts the content on a scrolling sheet (PDF, HTML, CSV, text, details).
   */
  import Icon from '../Icon.svelte'
  import { portal } from '../../lib/files/attachments.js'

  const CONTROL_ICON_SIZE = 20

  let { title, subtitle = '', label = title, downloadHref = '', variant = 'image', onClose, actions, children } = $props()

  let closeButton = $state(null)

  function closeOnEscape(event) {
    if (event.key !== 'Escape') return
    event.preventDefault()
    event.stopPropagation()
    onClose()
  }

  function closeOnBackdrop(event) {
    if (event.target === event.currentTarget) onClose()
  }

  // Focus moves into the viewer and back to where it was when the viewer closes.
  $effect(() => {
    const previous = document.activeElement
    closeButton?.focus()
    return () => previous?.focus?.()
  })
</script>

<svelte:window onkeydowncapture={closeOnEscape} />

<div class="viewer" class:document={variant === 'document'} role="dialog" aria-modal="true" aria-label={label} {@attach portal}>
  <header class="viewer-bar">
    <div class="viewer-title">
      <strong>{title}</strong>
      {#if subtitle}<small>{subtitle}</small>{/if}
    </div>
    {@render actions?.()}
    {#if downloadHref}
      <a class="viewer-control" href={downloadHref} download aria-label={`Download ${title}`} title="Download"><Icon name="download" size={CONTROL_ICON_SIZE} /></a>
    {/if}
    <button bind:this={closeButton} type="button" class="viewer-control" aria-label="Close viewer" title="Close" onclick={onClose}><Icon name="close" size={CONTROL_ICON_SIZE} /></button>
  </header>
  <div class="viewer-stage" role="presentation" onclick={closeOnBackdrop}>
    {#if variant === 'document'}
      <article class="sheet">{@render children()}</article>
    {:else}
      {@render children()}
    {/if}
  </div>
</div>

<style>
  .viewer {
    position: fixed; inset: 0; z-index: 80;
    display: flex; flex-direction: column;
    background: var(--viewer-bg); color: var(--on-viewer);
    font: 400 14px/1.5 var(--font);
  }
  .viewer-bar {
    display: flex; align-items: center; gap: 8px; flex-shrink: 0;
    padding: max(10px, env(safe-area-inset-top)) 12px 10px 20px;
  }
  .viewer-title { display: grid; flex: 1; min-width: 0; }
  .viewer-title strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font: 600 15px/1.35 var(--font); }
  .viewer-title small { color: var(--on-viewer-2); font: 400 12.5px/1.35 var(--font); }
  .viewer :global(.viewer-control) {
    display: inline-grid; place-items: center; flex-shrink: 0;
    width: 40px; height: 40px; padding: 0;
    border: 0; border-radius: var(--radius-pill);
    background: var(--viewer-control); color: var(--on-viewer);
  }
  .viewer :global(.viewer-control:hover:not(:disabled)) { background: var(--viewer-control-hover); }
  .viewer :global(.viewer-control:disabled) { opacity: .35; }
  .viewer-stage {
    position: relative; flex: 1; min-height: 0;
    display: flex; align-items: center; justify-content: center;
    padding: 0 16px max(16px, env(safe-area-inset-bottom));
  }
  .document .viewer-stage { align-items: stretch; }
  .sheet {
    width: min(900px, 100%); overflow-y: auto; overscroll-behavior: contain;
    padding: 20px; border-radius: var(--radius-card);
    background: var(--surface); color: var(--text);
  }
  @media (max-width: 520px) {
    .viewer-bar { padding-left: 16px; }
    .viewer-stage { padding: 0 0 env(safe-area-inset-bottom); }
    .sheet { padding: 16px; border-radius: var(--radius-card) var(--radius-card) 0 0; }
  }
</style>
