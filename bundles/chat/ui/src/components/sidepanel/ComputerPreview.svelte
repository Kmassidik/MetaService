<script>
  /**
   * The Computer tab: a small view-only picture of the screen, refreshed while the tab shows.
   * Hover (always on touch) shows Open, which opens the big view; an asleep computer wakes instead.
   * On a computer with the real desktop (C21) the picture is the live stream, watch-only.
   */
  import Icon from '../Icon.svelte'
  import RuviHero from '../RuviHero.svelte'
  import { PREVIEW_TONE } from '../../lib/sidePanel.js'
  import { ICON_SIZE } from '../../lib/constants.js'

  const CAPTION = 'Your computer'
  const ASLEEP_TEXT = 'Asleep'
  const EMPTY_TEXT = 'Nothing on screen yet'
  const RUVI_WIDTH = 96

  let { image = '', stream = '', line, waking = false, onOpen, onWake } = $props()

  const asleep = $derived(line.tone === PREVIEW_TONE.asleep)
  const starting = $derived(!image && !stream && line.tone === PREVIEW_TONE.busy)
  const placeholderText = $derived(emptyScreenText())

  // While starting, the status line below already says what's happening.
  function emptyScreenText() {
    if (asleep) return ASLEEP_TEXT
    return starting ? '' : EMPTY_TEXT
  }
</script>

<div class="preview">
  <button
    type="button"
    class="screen"
    class:is-asleep={asleep}
    disabled={waking}
    aria-label={asleep ? 'Wake your computer' : 'Open your computer'}
    onclick={asleep ? onWake : onOpen}
  >
    {#if stream && !asleep}
      <iframe class="live" title="Your computer’s screen, live" src={stream} tabindex="-1"></iframe>
    {:else if image}
      <img src={image} alt="Your computer’s screen" draggable="false" />
    {:else}
      <span class="placeholder"><RuviHero pose="setting-up" width={RUVI_WIDTH} variant="inline" />{placeholderText}</span>
    {/if}
    {#if !asleep}<span class="open-pill" aria-hidden="true"><Icon name="expand" size={ICON_SIZE.chevron} />Open</span>{/if}
  </button>
  <p class="caption">{CAPTION}</p>
  {#if line.wake}
    <button type="button" class="status is-wake" disabled={waking} onclick={onWake}>{waking ? 'Waking…' : line.text}</button>
  {:else}
    <p class="status" data-tone={line.tone}><span class="dot" aria-hidden="true"></span>{line.text}</p>
  {/if}
</div>

<style>
  .preview { display: grid; justify-items: center; gap: 6px; padding: 6px 16px 24px; }
  .screen {
    position: relative;
    display: grid;
    place-items: center;
    width: 100%;
    aspect-ratio: 16 / 10;
    padding: 0;
    overflow: hidden;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-control);
    background: var(--page);
    box-shadow: var(--shadow-float);
    cursor: pointer;
  }
  .screen:disabled { cursor: default; }
  .screen:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .screen img { display: block; width: 100%; height: 100%; object-fit: cover; object-position: top center; user-select: none; }
  .live { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; background: var(--stream-bg); pointer-events: none; }
  .placeholder { display: grid; justify-items: center; gap: 8px; color: var(--text-3); font: 400 var(--fs-preview)/1.3 var(--font); }
  .screen.is-asleep { background: var(--group); }
  .open-pill {
    position: absolute;
    top: 50%;
    left: 50%;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 34px;
    padding: 0 14px;
    border-radius: var(--radius-pill);
    background: var(--ink);
    color: var(--on-ink);
    font: 500 var(--fs-preview)/1 var(--font);
    opacity: 0;
    transform: translate(-50%, -50%);
    transition: opacity .15s ease;
  }
  .screen:hover .open-pill, .screen:focus-visible .open-pill { opacity: 1; }
  @media (hover: none) { .open-pill { opacity: 1; } }
  .caption { margin-top: 6px; color: var(--text); font: 500 var(--fs-preview)/1.3 var(--font); }
  .status { display: inline-flex; align-items: center; gap: 6px; color: var(--text-2); font: 400 var(--fs-time)/1.3 var(--font); }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--text-3); }
  .status[data-tone="busy"] .dot, .status[data-tone="control"] .dot { background: var(--brand-green-d); }
  .status.is-wake { padding: 2px 6px; border: 0; border-radius: var(--radius-item); background: none; cursor: pointer; text-decoration: underline; text-underline-offset: 3px; }
  .status.is-wake:hover:not(:disabled) { color: var(--text); }
</style>
