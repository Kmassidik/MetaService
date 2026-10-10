<script>
  import Icon from '../Icon.svelte'
  import BotAvatar from '../BotAvatar.svelte'
  import StackedAvatars from '../chrome/StackedAvatars.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'

  // The centered name pill, and the side panel's toggle at the top right.
  const PILL_AVATAR_SIZE = 22
  // Two overlapped faces need a larger slot to stay legible inside the 36 pt pill.
  const GROUP_PILL_AVATAR_SIZE = 28
  const STACKED_FACES = 2

  let {
    active = null,
    mobileRail = $bindable(false),
    members = [],
    panelOpen = false,
    panelId = '',
    onOpenDetails,
    onTogglePanel,
  } = $props()

  const isGroup = $derived(active?.kind === 'team')
  const faces = $derived(members.length ? members.slice(0, STACKED_FACES) : [active].filter(Boolean))
</script>

<header class="header">
  <div class="leading">
    <button class="icon-button mobile-only" aria-label="Back to bots" aria-controls="bot-navigation" aria-expanded={mobileRail} onclick={() => mobileRail = true}><Icon name="back" size={22} /></button>
  </div>
  {#if active && isGroup}
    <button type="button" class="pill group" aria-label={`Group details for ${active.name}`} onclick={onOpenDetails}>
      <StackedAvatars agents={faces} size={GROUP_PILL_AVATAR_SIZE} ring="var(--page)" />
      <span class="name">{active.name}</span>
    </button>
  {:else if active}
    <button type="button" class="pill" aria-label={`Details for ${active.name}`} onclick={onOpenDetails}>
      <BotAvatar agent={active} size={PILL_AVATAR_SIZE} />
      <span class="name">{active.name}</span>
    </button>
  {:else}
    <span></span>
  {/if}
  <div class="trailing">
    {#if active}
      <button type="button" class="icon-button panel-toggle" aria-label={panelOpen ? 'Hide details' : 'Show details'} title="Details" aria-controls={panelOpen ? panelId : undefined} aria-pressed={panelOpen} onclick={onTogglePanel}>
        <Icon name="panel" size={ICON_SIZE.header} />
      </button>
    {/if}
  </div>
</header>

<style>
  .header {
    display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; gap: 12px;
    min-height: 60px; padding: 12px 20px; flex-shrink: 0; background: var(--page);
  }
  .leading { justify-self: start; }
  .trailing { justify-self: end; }
  .pill {
    display: inline-flex; align-items: center; gap: 8px; max-width: min(360px, 60vw); height: 36px; padding: 0 16px 0 7px;
    border: 1px solid var(--hairline); border-radius: var(--radius-pill);
    background: var(--surface); box-shadow: var(--shadow-float); color: var(--text); cursor: pointer;
  }
  /* The stacked pair is wider than one face, so it gets the same breathing room as a single face. */
  .pill.group { padding-left: 10px; }
  .pill:hover { background: var(--sidebar); }
  .pill:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font: 500 var(--fs-pill)/1.2 var(--font); }
  /* Matches the pill: a 36 pt round button with the same hairline and float. */
  .panel-toggle { width: 36px; height: 36px; border-color: var(--hairline); background: var(--surface); box-shadow: var(--shadow-float); color: var(--text); }
  .panel-toggle[aria-pressed="true"] { background: var(--row-selected); }
  .panel-toggle:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  @media (max-width: 820px) { .header { padding: 10px 12px; } }
</style>
