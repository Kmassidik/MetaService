<script>
  /** The floating way out of full screen; it fades after a few idle seconds (see fullScreen.js). */
  import Icon from '../Icon.svelte'

  let { visible = false, onExit } = $props()

  const ICON_SIZE = 15
</script>

<button type="button" class="desk-fs-exit" class:is-visible={visible} aria-label="Exit full screen" tabindex={visible ? 0 : -1} onclick={onExit}>
  <Icon name="fullscreen-exit" size={ICON_SIZE} />Exit full screen
</button>

<style>
  .desk-fs-exit {
    position: absolute;
    top: 12px;
    left: 50%;
    z-index: 5;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    height: 34px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius-pill);
    background: var(--tooltip-bg);
    color: var(--tooltip-text);
    font: 500 var(--fs-preview)/1 var(--font);
    box-shadow: var(--shadow-float);
    cursor: pointer;
    opacity: 0;
    pointer-events: none;
    transform: translate(-50%, -6px);
    transition: opacity .2s ease, transform .2s ease;
  }
  .desk-fs-exit.is-visible { opacity: .92; pointer-events: auto; transform: translate(-50%, 0); }
  .desk-fs-exit.is-visible:hover { opacity: 1; }
  @media (prefers-reduced-motion: reduce) {
    .desk-fs-exit { transition: none; }
  }
</style>
