<script>
  /** One 58 pt sidebar row: face, name, one-line preview, unread badge and a hover ⋯. */
  import Icon from '../Icon.svelte'
  import BotAvatar from '../BotAvatar.svelte'
  import StackedAvatars from './StackedAvatars.svelte'
  import { isTeam } from '../../lib/chat/roster.js'

  let {
    agent,
    faces = [],
    preview = '',
    unread = '',
    busy = false,
    selected = false,
    onSelect,
    onMenu,
    onAvatar,
  } = $props()

  const AVATAR_SIZE = 36
  const LONG_PRESS_MS = 480
  // A long-press is followed by a synthetic click; ignore it, but not forever.
  const CLICK_GUARD_MS = 600
  // A group's pair is ringed in the row's current fill (idle, hover or selected), set in CSS.
  const ROW_FILL = 'var(--row-fill)'

  let pressTimer = null
  let suppressClick = false
  let pressing = $state(false)

  function pointFrom(event) {
    const rect = event.currentTarget.getBoundingClientRect()
    return { x: event.clientX || rect.right, y: event.clientY || rect.bottom }
  }

  function openMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    onMenu?.(agent, pointFrom(event))
  }

  function openAvatar(event) {
    event.stopPropagation()
    const rect = event.currentTarget.getBoundingClientRect()
    onAvatar?.(agent, { x: rect.left, y: rect.bottom })
  }

  function activate(event) {
    if (!suppressClick) return onSelect?.(agent)
    suppressClick = false
    event.preventDefault()
  }

  function startLongPress(event) {
    const touch = event.touches?.[0]
    if (!touch) return
    cancelLongPress()
    pressing = true
    pressTimer = setTimeout(() => firePress(touch), LONG_PRESS_MS)
  }

  function firePress(touch) {
    pressing = false
    suppressClick = true
    onMenu?.(agent, { x: touch.clientX, y: touch.clientY })
    setTimeout(() => { suppressClick = false }, CLICK_GUARD_MS)
  }

  function cancelLongPress() {
    clearTimeout(pressTimer)
    pressTimer = null
    pressing = false
  }
</script>

<!-- Sibling buttons (avatar, row, ⋯) rather than buttons nested in a role="button" row. -->
<div
  class="roster-row"
  class:selected
  class:pressing
  role="presentation"
  oncontextmenu={openMenu}
  ontouchstart={startLongPress}
  ontouchend={cancelLongPress}
  ontouchmove={cancelLongPress}
  ontouchcancel={cancelLongPress}
>
  {#if !isTeam(agent)}
    <button type="button" class="roster-avatar" aria-label={`Change avatar for ${agent.name}`} onclick={openAvatar}>
      <BotAvatar {agent} size={AVATAR_SIZE} />
    </button>
  {/if}
  <button type="button" class="roster-main" aria-current={selected ? 'page' : undefined} onclick={activate}>
    {#if isTeam(agent)}<StackedAvatars agents={faces} size={AVATAR_SIZE} ring={ROW_FILL} />{/if}
    <span class="roster-copy">
      <span class="roster-name">{agent.name}</span>
      {#if preview}<span class="roster-preview">{preview}</span>{/if}
    </span>
    {#if busy}<span class="tiny-spinner" aria-label="Working"></span>{/if}
    {#if unread}<span class="roster-unread" aria-label={`${unread} unread`}>{unread}</span>{/if}
  </button>
  <button type="button" class="roster-more" aria-label={`Actions for ${agent.name}`} onclick={openMenu}><Icon name="more" size={16} /></button>
</div>

<style>
  .roster-row {
    position: relative;
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 58px;
    padding: 0 10px;
    border-radius: var(--radius-control);
    color: var(--text);
    -webkit-touch-callout: none;
    user-select: none;
  }
  /* One fill token per state; the selected row is a soft fill and nothing else. */
  .roster-row { --row-fill: var(--sidebar); background: var(--row-fill); }
  .roster-row:hover { --row-fill: var(--row-hover); }
  .roster-row.selected, .roster-row.pressing { --row-fill: var(--row-selected); }
  .roster-main {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: 1;
    min-width: 0;
    min-height: 58px;
    padding: 0;
    border: 0;
    background: transparent;
    color: inherit;
    font: inherit;
    text-align: left;
    cursor: pointer;
  }
  .roster-main:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: -2px; border-radius: var(--radius-control); }
  .roster-avatar {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    padding: 0;
    border: 0;
    border-radius: var(--radius-avatar);
    background: transparent;
    line-height: 0;
    cursor: pointer;
  }
  .roster-avatar:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .roster-copy { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
  .roster-name, .roster-preview { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .roster-name { color: var(--text); font: 500 var(--fs-name)/1.3 var(--font); }
  .roster-preview { color: var(--text-2); font: 400 var(--fs-preview)/1.35 var(--font); }
  .roster-unread {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    min-width: 20px;
    height: 20px;
    padding: 0 6px;
    border-radius: var(--radius-pill);
    background: var(--ink);
    color: var(--on-ink);
    font: 600 12px/1 var(--font);
  }
  .roster-more {
    position: absolute;
    right: 8px;
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    padding: 0;
    border: 0;
    border-radius: var(--radius-pill);
    background: var(--surface);
    color: var(--text-2);
    box-shadow: var(--shadow-float);
    opacity: 0;
    pointer-events: none;
  }
  /* Keyboard focus reveals ⋯; a mouse click that leaves focus behind does not (reference: hover only). */
  .roster-row:hover .roster-more,
  .roster-row:has(:focus-visible) .roster-more { opacity: 1; pointer-events: auto; }
  .roster-more:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .roster-more:hover { color: var(--text); }
  /* Touch has no hover: keep a quiet ⋯ visible so the actions stay discoverable. */
  @media (hover: none) {
    .roster-more { position: static; opacity: 1; pointer-events: auto; background: transparent; box-shadow: none; }
  }
</style>
