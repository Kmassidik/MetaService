<script>
  import Icon from '../Icon.svelte'

  // items: [{ id, label, icon, disabled, onSelect }]
  let { items = [], label = 'More options' } = $props()

  let open = $state(false)
  let root = $state(null)

  function toggle() {
    open = !open
  }

  function choose(item) {
    open = false
    item.onSelect()
  }

  function closeOnOutsideClick(event) {
    if (!open || root?.contains(event.target)) return
    open = false
  }

  function closeOnEscape(event) {
    if (!open || event.key !== 'Escape') return
    // Stop here so Esc closes only the menu, not the whole computer panel.
    event.stopPropagation()
    open = false
  }
</script>

<svelte:window onclick={closeOnOutsideClick} />

<div class="desk-menu" bind:this={root} role="presentation" onkeydown={closeOnEscape}>
  <button type="button" class="icon-button" aria-label={label} aria-haspopup="menu" aria-expanded={open} onclick={toggle}>
    <Icon name="more" size={18} />
  </button>
  {#if open}
    <div class="desk-menu-list" role="menu">
      {#each items as item (item.id)}
        <button type="button" role="menuitem" disabled={item.disabled} onclick={() => choose(item)}>
          <Icon name={item.icon} size={16} />{item.label}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .desk-menu { position: relative; }
  .desk-menu-list {
    position: absolute;
    top: calc(100% + 6px);
    right: 0;
    z-index: 5;
    min-width: 220px;
    padding: 6px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-menu);
    background: var(--surface);
    box-shadow: var(--shadow-float);
  }
  .desk-menu-list button {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 9px 10px;
    border: 0;
    border-radius: var(--radius-item);
    background: none;
    color: var(--text);
    font: 400 var(--fs-menu)/1.3 var(--font);
    text-align: left;
    cursor: pointer;
  }
  .desk-menu-list button:hover:not(:disabled) { background: var(--row-hover); }
  .desk-menu-list button:disabled { color: var(--text-3); cursor: default; }
</style>
