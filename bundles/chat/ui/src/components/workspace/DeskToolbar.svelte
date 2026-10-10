<script>
  import Icon from '../Icon.svelte'
  import DeskMenu from './DeskMenu.svelte'

  let {
    title = '',
    liveText = '',
    live = false,
    busy = false,
    showTakeover = false,
    takingOver = false,
    takeoverDisabled = true,
    menuItems = [],
    showFullScreen = false,
    fullScreen = false,
    onToggleFullScreen,
    onTakeOver,
    onHandBack,
    onClose,
  } = $props()

  const ICON_SIZE = 15
  const fullScreenLabel = $derived(fullScreen ? 'Exit full screen' : 'Full screen')
</script>

<header class="desk-toolbar">
  <button type="button" class="desk-back" onclick={onClose}>
    <Icon name="chevron" size={16} class="desk-back-icon" />Back to chat
  </button>
  <div class="desk-title">
    <h2>{title}</h2>
    {#if liveText}
      <span class="desk-live" class:is-live={live}><span class="desk-live-dot" aria-hidden="true"></span>{liveText}</span>
    {/if}
    {#if busy}<span class="tiny-spinner" aria-label="Updating computer"></span>{/if}
  </div>
  <div class="desk-actions">
    {#if showTakeover && takingOver}
      <button type="button" class="desk-pill is-active" aria-label="Give back" disabled={takeoverDisabled} onclick={onHandBack}><Icon name="check" size={15} /><span class="desk-pill-label">Give back</span></button>
    {:else if showTakeover}
      <button type="button" class="desk-pill" aria-label="Take control" disabled={takeoverDisabled} onclick={onTakeOver}><Icon name="pointer" size={15} /><span class="desk-pill-label">Take control</span></button>
    {/if}
    {#if showFullScreen}
      <button type="button" class="desk-pill" class:is-on={fullScreen} aria-label={fullScreenLabel} aria-pressed={fullScreen} title={fullScreenLabel} onclick={onToggleFullScreen}>
        <Icon name={fullScreen ? 'fullscreen-exit' : 'fullscreen'} size={ICON_SIZE} /><span class="desk-pill-label">{fullScreenLabel}</span>
      </button>
    {/if}
    {#if menuItems.length}<DeskMenu items={menuItems} label="More computer options" />{/if}
    <button type="button" class="icon-button desk-close" aria-label="Close computer" onclick={onClose}><Icon name="close" size={17} /></button>
  </div>
</header>

<style>
  .desk-toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-shrink: 0;
    min-height: 56px;
    padding: 10px 12px 10px 18px;
    border-bottom: 1px solid var(--hairline);
    background: var(--page);
  }
  .desk-title { display: flex; align-items: center; gap: 10px; flex: 1; min-width: 0; }
  .desk-title h2 {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--text);
    font: 600 var(--fs-name)/1.3 var(--font);
  }
  .desk-live { display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; color: var(--text-2); font: 500 var(--fs-time)/1 var(--font); }
  .desk-live-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--text-3); }
  .desk-live.is-live .desk-live-dot { background: var(--brand-green-d); box-shadow: 0 0 0 3px color-mix(in srgb, var(--brand-green) 25%, transparent); }
  .desk-actions { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
  .desk-pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    margin-right: 4px;
    padding: 0 13px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--page);
    color: var(--text);
    font: 500 var(--fs-preview)/1 var(--font);
    cursor: pointer;
  }
  .desk-pill:hover:not(:disabled) { background: var(--row-hover); }
  .desk-pill:disabled { color: var(--text-3); cursor: default; }
  .desk-pill.is-on { background: var(--tint-selected); }
  .desk-pill.is-active { border-color: var(--ink); background: var(--ink); color: var(--on-ink); }
  .desk-pill.is-active:disabled { color: var(--on-ink); opacity: .55; }
  .desk-back {
    display: none;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
    height: 32px;
    padding: 0 12px 0 8px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--surface);
    color: var(--text);
    font: 500 var(--fs-preview)/1 var(--font);
    box-shadow: var(--shadow-float);
    cursor: pointer;
  }
  .desk-back :global(.desk-back-icon) { transform: rotate(180deg); }
  .desk-back:hover { background: var(--row-hover); }
  @media (max-width: 820px) {
    .desk-toolbar { padding-left: 12px; }
    .desk-back { display: inline-flex; }
    .desk-close { display: none; }
    .desk-pill { padding: 0 9px; }
    .desk-pill-label, .desk-live { display: none; }
  }
</style>
