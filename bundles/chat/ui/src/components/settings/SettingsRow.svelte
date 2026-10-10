<script>
  /**
   * One Settings row: label (and an optional detail line) on the left, a value or a control on
   * the right. With `onclick` the whole row is a button with a chevron; `tone="danger"` reds it.
   */
  import Icon from '../Icon.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'

  let { label, detail = '', value = '', onclick = undefined, disabled = false, tone = '', children = undefined } = $props()
</script>

{#snippet body()}
  <span class="row-text"><span class="row-label">{label}</span>{#if detail}<small>{detail}</small>{/if}</span>
  {#if value}<span class="row-value">{value}</span>{/if}
  {@render children?.()}
{/snippet}

{#if onclick}
  <button type="button" class="settings-row is-button" class:danger={tone === 'danger'} {disabled} {onclick}>
    {@render body()}{#if tone !== 'danger'}<Icon name="chevron" size={ICON_SIZE.chevron} />{/if}
  </button>
{:else}
  <div class="settings-row">{@render body()}</div>
{/if}

<style>
  .settings-row { display: flex; align-items: center; gap: 12px; width: 100%; min-height: 48px; padding: 10px 14px; background: transparent; color: var(--text); font: 400 var(--fs-menu)/1.35 var(--font); text-align: left; }
  .row-text { display: grid; flex: 1; min-width: 0; }
  .row-label { overflow-wrap: anywhere; }
  small { color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  .row-value { min-width: 0; max-width: 60%; color: var(--text-2); text-align: right; overflow-wrap: anywhere; }
  .is-button { border-radius: 0; }
  .is-button :global(svg) { color: var(--text-3); }
  @media (hover: hover) {
    .is-button:hover:not(:disabled) { background: var(--tint-hover); }
  }
  .is-button:focus-visible { outline-offset: -2px; }
  .danger { color: var(--danger); }
</style>
