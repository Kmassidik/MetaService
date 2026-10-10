<script>
  /** The Settings section list: a left column on desktop, the first screen on a phone. */
  import Icon from '../Icon.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'
  import { SETTINGS, SETTINGS_SECTIONS } from '../../lib/settingsSections.js'

  let { current, locked = false, onSelect } = $props()
</script>

<nav class="settings-nav" aria-label="Settings sections">
  {#each SETTINGS_SECTIONS as section (section.id)}
    <button
      type="button"
      class="nav-item"
      class:danger={section.id === SETTINGS.danger}
      aria-current={current === section.id ? 'page' : undefined}
      disabled={locked}
      onclick={() => onSelect(section.id)}
    >
      <Icon name={section.icon} size={ICON_SIZE.list} />
      <span>{section.label}</span>
      <Icon name="chevron" size={ICON_SIZE.chevron} class="nav-chevron" />
    </button>
  {/each}
</nav>

<style>
  .settings-nav { display: flex; flex-direction: column; gap: 2px; }
  .nav-item { display: flex; align-items: center; gap: 11px; min-height: 38px; padding: 8px 10px; border-radius: var(--radius-control); background: transparent; color: var(--text); font: 400 var(--fs-menu)/1.3 var(--font); text-align: left; }
  .nav-item span { flex: 1; }
  .nav-item :global(svg) { color: var(--text-2); }
  @media (hover: hover) {
    .nav-item:hover:not(:disabled) { background: var(--tint-hover); }
  }
  .nav-item[aria-current="page"] { background: var(--tint-selected); font-weight: 500; }
  .nav-item[aria-current="page"] :global(svg) { color: var(--text); }
  .danger, .danger :global(svg) { color: var(--danger); }
  .nav-item :global(.nav-chevron) { display: none; }
  /* Phone: one grouped card of rows with chevrons, like the top level of iOS Settings. */
  @media (max-width: 520px) {
    .settings-nav { gap: 0; overflow: hidden; border-radius: var(--radius-card); background: var(--group); }
    .nav-item { position: relative; min-height: 50px; padding: 12px 14px; border-radius: 0; }
    .nav-item + .nav-item::before { content: ''; position: absolute; top: 0; left: 42px; right: 0; height: 1px; background: var(--group-line); }
    .nav-item[aria-current="page"] { background: transparent; font-weight: 400; }
    .nav-item :global(.nav-chevron) { display: block; color: var(--text-3); }
  }
</style>
