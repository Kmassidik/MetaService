<script>
  /**
   * Shared shell for sidebar menus (bot actions, new chat, account): backdrop, Esc, viewport
   * clamping and the shared menu look. On phones it becomes a bottom sheet.
   * Items use the global `.menu-item` / `.menu-divider` classes defined below.
   */
  let {
    open = false,
    x = 0,
    y = 0,
    placement = 'down',
    label = 'Menu',
    onClose,
    children,
  } = $props()

  const VIEWPORT_MARGIN = 8

  let panelWidth = $state(0)
  let panelHeight = $state(0)
  let viewportWidth = $state(0)
  let viewportHeight = $state(0)

  function clamp(value, size, limit) {
    return Math.max(VIEWPORT_MARGIN, Math.min(value, limit - size - VIEWPORT_MARGIN))
  }

  const left = $derived(clamp(x, panelWidth, viewportWidth))
  const top = $derived(clamp(placement === 'up' ? y - panelHeight : y, panelHeight, viewportHeight))

  function onKey(event) {
    if (open && event.key === 'Escape') onClose?.()
  }
</script>

<svelte:window onkeydown={onKey} bind:innerWidth={viewportWidth} bind:innerHeight={viewportHeight} />

{#if open}
  <button type="button" class="floating-menu-backdrop" aria-label="Close menu" onclick={onClose}></button>
  <div
    class="floating-menu"
    style:left={`${left}px`}
    style:top={`${top}px`}
    role="menu"
    aria-label={label}
    bind:offsetWidth={panelWidth}
    bind:offsetHeight={panelHeight}
  >
    {@render children?.()}
  </div>
{/if}

<style>
  .floating-menu-backdrop {
    position: fixed;
    inset: 0;
    z-index: 70;
    border: 0;
    padding: 0;
    background: transparent;
    cursor: default;
  }
  .floating-menu {
    position: fixed;
    z-index: 71;
    min-width: 220px;
    max-width: min(300px, calc(100vw - 16px));
    padding: 6px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-menu);
    background: var(--surface);
    box-shadow: var(--shadow-float);
  }
  .floating-menu :global(.menu-item) {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    min-height: 36px;
    padding: 8px 10px;
    border: 0;
    border-radius: var(--radius-item);
    background: transparent;
    color: var(--text);
    font: 400 var(--fs-menu)/1.3 var(--font);
    text-align: left;
    cursor: pointer;
  }
  .floating-menu :global(.menu-item:hover:not(:disabled)),
  .floating-menu :global(.menu-item:focus-visible) { background: var(--row-hover); outline: none; }
  .floating-menu :global(.menu-item:disabled) { color: var(--text-3); cursor: default; }
  .floating-menu :global(.menu-item.danger) { color: var(--danger); }
  .floating-menu :global(.menu-item svg) { flex-shrink: 0; color: var(--text-2); }
  .floating-menu :global(.menu-item-trail) { margin-left: auto; color: var(--text-2); }
  .floating-menu :global(.menu-note) {
    margin: 0;
    padding: 0 10px 8px 38px;
    color: var(--text-2);
    font: 400 var(--fs-preview)/1.35 var(--font);
  }
  .floating-menu :global(.menu-divider) { margin: 6px 4px; border: 0; border-top: 1px solid var(--hairline); }

  @media (max-width: 520px) {
    .floating-menu-backdrop { background: var(--scrim); }
    .floating-menu {
      inset: auto 0 0 0 !important;
      max-width: none;
      padding: 10px 10px calc(10px + env(safe-area-inset-bottom));
      border-radius: var(--radius-card) var(--radius-card) 0 0;
      box-shadow: var(--shadow-sheet);
    }
    .floating-menu :global(.menu-item) { min-height: 48px; }
  }
</style>
