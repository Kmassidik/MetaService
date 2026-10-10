<script>
  /**
   * A picture in the composer: a small square that shows upload progress as a ring, then the
   * picture itself (tap to view). The corner × removes it or cancels the upload.
   * Pass `file` for a ready attachment or `upload` for one still uploading (a failed upload is a text chip).
   */
  import Icon from '../Icon.svelte'
  import Thumbnail from './Thumbnail.svelte'

  const RING_RADIUS = 15
  const RING_LENGTH = 2 * Math.PI * RING_RADIUS
  const PERCENT = 100
  const REMOVE_ICON_SIZE = 12

  let { file = null, upload = null, removeLabel, removeDisabled = false, onOpen, onRemove } = $props()

  const name = $derived(file?.name || upload?.name || '')
  const progress = $derived(upload ? Math.min(1, upload.received / (upload.size || 1)) : 1)
  const status = $derived(upload ? `${upload.status} ${Math.round(progress * PERCENT)}%` : 'Ready')
</script>

<li class="tile" title={`${name} · ${status}`}>
  {#if file}
    <button type="button" class="picture" aria-label={`View ${name}`} onclick={onOpen}>
      <Thumbnail {file} alt={name} />
    </button>
  {:else}
    <span class="picture" role="progressbar" aria-label={`Upload progress for ${name}`} aria-valuemin="0" aria-valuemax={PERCENT} aria-valuenow={Math.round(progress * PERCENT)}>
      <svg viewBox="0 0 36 36" aria-hidden="true">
        <circle class="track" cx="18" cy="18" r={RING_RADIUS} />
        <circle class="bar" cx="18" cy="18" r={RING_RADIUS} stroke-dasharray={RING_LENGTH} stroke-dashoffset={RING_LENGTH * (1 - progress)} />
      </svg>
    </span>
  {/if}
  <button type="button" class="remove" aria-label={removeLabel} disabled={removeDisabled} onclick={onRemove}><Icon name="close" size={REMOVE_ICON_SIZE} /></button>
</li>

<style>
  .tile { position: relative; flex-shrink: 0; width: 56px; height: 56px; }
  .picture {
    display: grid; place-items: center; overflow: hidden;
    width: 100%; height: 100%; padding: 0;
    border-radius: var(--radius-control); background: var(--bubble); color: var(--text-2);
  }
  button.picture { cursor: zoom-in; }
  svg { width: 30px; height: 30px; transform: rotate(-90deg); }
  circle { fill: none; stroke-width: 3; }
  .track { stroke: var(--hairline); }
  .bar { stroke: var(--text); stroke-linecap: round; transition: stroke-dashoffset .2s ease; }
  .remove {
    position: absolute; top: -6px; right: -6px;
    display: grid; place-items: center;
    width: 20px; height: 20px; padding: 0;
    border: 2px solid var(--surface); border-radius: var(--radius-pill);
    background: var(--text); color: var(--page);
  }
  .remove:hover:not(:disabled) { background: var(--text-2); }
</style>
