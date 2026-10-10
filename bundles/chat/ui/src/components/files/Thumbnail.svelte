<script>
  /**
   * A saved picture, fetched once per session through the shared cache and only when it scrolls
   * near the screen. Fills its parent: `fit="cover"` crops to a square tile, `fit="natural"` keeps
   * the picture's shape. Falls back to the file's type icon when it can't be shown.
   */
  import Icon from '../Icon.svelte'
  import { thumbnails } from '../../lib/files/thumbnails.js'
  import { whenVisible } from '../../lib/files/attachments.js'
  import { fileIcon } from '../../lib/files/preview.js'

  const FALLBACK_ICON_SIZE = 20

  let { file, alt = '', fit = 'cover' } = $props()

  let loaded = $state('')
  let failed = $state(false)
  const url = $derived(loaded || thumbnails.peek(file.id))

  function load() {
    thumbnails.get(file).then(found => { loaded = found }, () => { failed = true })
  }
</script>

<span class="thumb" class:natural={fit === 'natural'} class:waiting={failed || !url} {@attach whenVisible(load)}>
  {#if failed}
    <Icon name={fileIcon(file)} size={FALLBACK_ICON_SIZE} />
  {:else if url}
    <img src={url} {alt} draggable="false" onerror={() => { failed = true }} />
  {/if}
</span>

<style>
  .thumb {
    display: grid; place-items: center; overflow: hidden;
    width: 100%; height: 100%;
    background: var(--bubble); color: var(--text-2);
  }
  .thumb img { display: block; width: 100%; height: 100%; object-fit: cover; }
  /* The picture sets the size (≤ 360 px tall, ≤ its container wide); a placeholder holds 4:3 until it loads. */
  .natural { width: auto; height: auto; }
  /* Tiny pictures (icons, a pixel) still get a tappable box; contain keeps their shape. */
  .natural img { width: auto; max-width: 100%; height: auto; max-height: 360px; min-width: 96px; min-height: 96px; object-fit: contain; }
  .natural.waiting { width: 240px; max-width: 100%; aspect-ratio: 4 / 3; }
</style>
