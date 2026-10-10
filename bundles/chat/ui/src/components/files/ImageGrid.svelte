<script>
  /** A message's pictures inline: one at its own shape (≤ 320 px), several as square tiles. Tap opens the viewer. */
  import Thumbnail from './Thumbnail.svelte'
  import ImageViewer from './ImageViewer.svelte'
  import { gridColumns } from '../../lib/files/imageGrid.js'

  const CLOSED = -1

  let { images = [] } = $props()

  let viewing = $state(CLOSED)
  const columns = $derived(gridColumns(images.length))
  const single = $derived(images.length === 1)
</script>

{#if images.length}
  <div class="image-grid" class:single style:--columns={columns} aria-label="Pictures">
    {#each images as image, position (image.id)}
      <button type="button" class="tile" aria-label={`Open ${image.name}`} onclick={() => { viewing = position }}>
        <Thumbnail file={image} alt={image.name} fit={single ? 'natural' : 'cover'} />
      </button>
    {/each}
  </div>
{/if}

{#if viewing !== CLOSED}
  <ImageViewer {images} bind:index={viewing} onClose={() => { viewing = CLOSED }} />
{/if}

<style>
  .image-grid {
    display: grid; grid-template-columns: repeat(var(--columns), minmax(0, 1fr)); gap: 4px;
    width: min(320px, 100%); margin-top: 6px;
  }
  .single { width: auto; max-width: min(320px, 100%); }
  .tile {
    display: block; padding: 0; overflow: hidden;
    aspect-ratio: 1; border-radius: var(--radius-item);
    background: var(--bubble); cursor: zoom-in;
  }
  .single .tile { aspect-ratio: auto; border-radius: var(--radius-bubble); }
</style>
