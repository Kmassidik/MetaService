<script>
  import Icon from '../Icon.svelte'

  // Every composer tool lives here, so the pill itself stays calm.
  let {
    open = $bindable(false),
    attachDisabled = false,
    toolsDisabled = false,
    onAttach,
    onFiles,
    onSkills,
    onMention,
    onTeach,
    onFind,
    onConnect,
    onHelp,
  } = $props()

  const primaryItems = $derived([
    { id: 'attach', icon: 'attach', label: 'Attach files', disabled: attachDisabled, run: onAttach },
    { id: 'files', icon: 'folder', label: 'Files & results', disabled: false, run: onFiles },
    { id: 'skills', icon: 'spark', label: 'Skills', hint: '/', disabled: toolsDisabled, run: onSkills },
    { id: 'mention', icon: 'at', label: 'Mention a bot', hint: '@', disabled: toolsDisabled, run: onMention },
    { id: 'teach', icon: 'pointer', label: 'Teach a task', disabled: false, run: onTeach },
    { id: 'connect', icon: 'plug', label: 'Connect an app', disabled: false, run: onConnect },
  ])
  const secondaryItems = $derived([
    // The only visible way into find-in-chat on phones, which have no Cmd/Ctrl+F.
    { id: 'find', icon: 'search', label: 'Find in chat', disabled: false, run: onFind },
    { id: 'help', icon: 'info', label: 'Help & limits', disabled: false, run: onHelp },
  ])

  function choose(item) {
    open = false
    item.run()
  }

  function closeOnEscape(event) {
    if (event.key !== 'Escape' || !open) return
    event.stopPropagation()
    open = false
  }
</script>

<svelte:window onkeydown={closeOnEscape} />

{#snippet menuItem(item)}
  <button type="button" role="menuitem" class="plus-item" disabled={item.disabled} onclick={() => choose(item)}>
    <Icon name={item.icon} size={18} />
    <span>{item.label}</span>
    {#if item.hint}<kbd>{item.hint}</kbd>{/if}
  </button>
{/snippet}

{#if open}
  <button type="button" class="plus-backdrop" aria-label="Close menu" onclick={() => open = false}></button>
  <div class="plus-menu" role="menu" aria-label="Message tools">
    {#each primaryItems as item (item.id)}{@render menuItem(item)}{/each}
    <hr />
    {#each secondaryItems as item (item.id)}{@render menuItem(item)}{/each}
  </div>
{/if}

<style>
  .plus-backdrop { position: fixed; inset: 0; z-index: 30; border: 0; padding: 0; background: transparent; cursor: default; }
  .plus-menu {
    position: absolute; left: 0; bottom: calc(100% + 8px); z-index: 31;
    min-width: 244px; padding: 6px;
    border: 1px solid var(--hairline); border-radius: var(--radius-menu);
    background: var(--surface); box-shadow: var(--shadow-float);
  }
  .plus-item {
    display: flex; align-items: center; gap: 12px; width: 100%;
    min-height: 38px; padding: 8px 10px;
    border: 0; border-radius: var(--radius-item);
    background: transparent; color: var(--text); text-align: left;
    font: 400 var(--fs-menu)/1.3 var(--font); cursor: pointer;
  }
  .plus-item > :global(svg) { color: var(--text-2); flex-shrink: 0; }
  .plus-item span { flex: 1; }
  .plus-item:hover:not(:disabled) { background: var(--row-hover); }
  .plus-item:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: -2px; }
  .plus-item:disabled { color: var(--text-3); cursor: not-allowed; }
  kbd { color: var(--text-3); font: 400 13px/1 var(--font); }
  hr { margin: 6px 8px; border: 0; border-top: 1px solid var(--hairline); }

  /* On phones the menu becomes a bottom sheet within thumb reach. */
  @media (max-width: 520px) {
    .plus-backdrop { background: var(--scrim); }
    .plus-menu {
      position: fixed; left: 0; right: 0; bottom: 0; min-width: 0;
      padding: 10px 10px calc(10px + env(safe-area-inset-bottom));
      border-radius: var(--radius-card) var(--radius-card) 0 0;
      box-shadow: var(--shadow-sheet);
    }
    .plus-item { min-height: 48px; }
  }
</style>
