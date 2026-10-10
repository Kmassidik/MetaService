<script>
  import BotAvatar from '../BotAvatar.svelte'
  import { avatarCatalog, isSameAvatar } from '../../lib/avatars.js'

  /** Grid of Ruvi's plush snake family, one per avatar colour. */
  let {
    agent = null,
    open = false,
    x = 0,
    y = 0,
    onPick,
    onClose,
  } = $props()

  // Keeps the popover on screen when opened near the right or bottom edge.
  const POPOVER_EDGE_ROOM_X = 300
  const POPOVER_EDGE_ROOM_Y = 220
  const PREVIEW_SIZE = 36

  const position = $derived(clampToViewport(x, y))

  function clampToViewport(left, top) {
    if (typeof window === 'undefined') return { left, top }
    return {
      left: Math.max(0, Math.min(left, window.innerWidth - POPOVER_EDGE_ROOM_X)),
      top: Math.max(0, Math.min(top, window.innerHeight - POPOVER_EDGE_ROOM_Y)),
    }
  }

  function isSelected(option) {
    return isSameAvatar(agent, option)
  }

  function pick(option) {
    onPick?.(option)
    onClose?.()
  }

  function onWindow(event) {
    if (event.key === 'Escape') onClose?.()
  }
</script>

<svelte:window onkeydown={onWindow} />

{#if open && agent}
  <button type="button" class="avatar-popover-backdrop" aria-label="Close avatar picker" onclick={onClose}></button>
  <div
    class="avatar-popover"
    style={`left:${position.left}px;top:${position.top}px`}
    role="dialog"
    aria-label="Choose avatar"
  >
    <p class="avatar-popover-title">Choose avatar</p>
    <div class="avatar-popover-grid">
      {#each avatarCatalog as option (option.color)}
        <button
          type="button"
          class="avatar-pick"
          class:selected={isSelected(option)}
          aria-label={`${option.name} snake`}
          onclick={() => pick(option)}
        ><BotAvatar agent={{ ...agent, avatarColor: option.color, avatarShape: option.shape }} size={PREVIEW_SIZE} /></button>
      {/each}
    </div>
  </div>
{/if}

<style>
  .avatar-popover-backdrop {
    position: fixed;
    inset: 0;
    z-index: 80;
    border: 0;
    padding: 0;
    background: transparent;
    cursor: default;
  }
  .avatar-popover {
    position: fixed;
    z-index: 81;
    width: 300px;
    max-height: min(440px, calc(100vh - 24px));
    overflow: auto;
    padding: 14px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-menu);
    background: var(--surface);
    box-shadow: var(--shadow-float);
  }
  .avatar-popover-title {
    margin: 0 0 12px;
    color: var(--text-2);
    font: 600 13px/1.4 var(--font);
  }
  .avatar-popover-grid {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 6px;
  }
  /* Padding leaves room for each face's drop shadow inside the hover tile. */
  .avatar-popover-grid :global(.avatar-pick) {
    display: grid;
    place-items: center;
    padding: 4px 0 6px;
    border: 0;
    background: transparent;
    border-radius: var(--radius-control);
    line-height: 0;
    cursor: pointer;
    transition: transform 0.14s ease, background-color 0.14s ease;
  }
  .avatar-popover-grid :global(.avatar-pick:hover) {
    background: var(--row-hover);
    transform: translateY(-1px);
  }
  .avatar-popover-grid :global(.avatar-pick:active) {
    background: var(--row-selected);
    transform: translateY(0);
  }
  .avatar-popover-grid :global(.avatar-pick.selected) {
    background: var(--row-selected);
    outline: 2px solid var(--ink);
    outline-offset: 0;
  }
</style>
