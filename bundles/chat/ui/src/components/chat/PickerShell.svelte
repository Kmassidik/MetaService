<script>
  import Icon from '../Icon.svelte'

  // Shared floating popover above the composer for the @ and / pickers.
  let { label, placeholder, query = $bindable(''), onClose, children } = $props()

  // Typing continues in the picker's own search once it opens.
  function focusOnMount(node) {
    node.focus()
  }

  function closeOnEscape(event) {
    if (event.key === 'Escape') onClose()
  }
</script>

<div class="picker" role="listbox" aria-label={label}>
  <div class="search">
    <Icon name="search" size={16} />
    <input type="search" {placeholder} aria-label={placeholder} value={query} oninput={event => query = event.currentTarget.value} onkeydown={closeOnEscape} use:focusOnMount />
    <button type="button" class="close" aria-label="Close" onclick={onClose}><Icon name="close" size={15} /></button>
  </div>
  <div class="options">{@render children()}</div>
</div>

<style>
  .picker {
    position: absolute; left: 28px; right: 28px; bottom: calc(100% - 4px); z-index: 25;
    display: grid; max-height: min(360px, 50dvh); padding: 6px;
    border: 1px solid var(--hairline); border-radius: var(--radius-menu);
    background: var(--surface); box-shadow: var(--shadow-float);
  }
  .search { display: flex; align-items: center; gap: 8px; padding: 4px 4px 8px 8px; border-bottom: 1px solid var(--hairline); color: var(--text-2); }
  /* The search sits inside the picker's own frame, so the global green input ring is not drawn. */
  input:focus-visible { outline: none; }
  input { flex: 1; min-width: 0; height: 30px; border: 0; outline: none; background: transparent; color: var(--text); font: 400 15px/1.3 var(--font); }
  .close { display: grid; place-items: center; width: 28px; height: 28px; padding: 0; border: 0; border-radius: var(--radius-pill); background: transparent; color: var(--text-2); cursor: pointer; }
  .close:hover { background: var(--row-hover); color: var(--text); }
  .options { min-height: 0; overflow-y: auto; padding-top: 4px; }
  .options :global(.picker-option) {
    display: flex; align-items: center; gap: 10px; width: 100%; padding: 8px 10px;
    border: 0; border-radius: var(--radius-item); background: transparent; color: var(--text); text-align: left; cursor: pointer;
  }
  .options :global(.picker-option:hover:not(:disabled)) { background: var(--row-hover); }
  .options :global(.picker-option:disabled) { opacity: .5; cursor: default; }
  .options :global(.picker-option span) { display: grid; min-width: 0; }
  .options :global(.picker-option strong) { font: 500 var(--fs-menu)/1.3 var(--font); }
  .options :global(.picker-option small) { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-2); font: 400 13px/1.35 var(--font); }
  .options :global(.picker-heading) { margin: 8px 10px 4px; color: var(--text-2); font: 500 var(--fs-time)/1.3 var(--font); }
  .options :global(.picker-empty) { margin: 10px; color: var(--text-2); font: 400 14px/1.45 var(--font); }
  .options :global(.picker-glyph) { display: grid; place-items: center; width: 28px; height: 28px; flex-shrink: 0; border-radius: var(--radius-pill); background: var(--bubble); color: var(--text-2); }
  @media (max-width: 820px) { .picker { left: 12px; right: 12px; } input { font-size: 16px; } }
</style>
