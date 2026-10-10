<script>
  /**
   * Full-screen picture viewer (Grok/ChatGPT style): the picture fit to the screen, its name and
   * Download, and ← → keys, swipes or the side buttons between the pictures of one message.
   * `index` is bound so the opener decides where it starts.
   */
  import Icon from '../Icon.svelte'
  import ViewerShell from './ViewerShell.svelte'
  import { thumbnails } from '../../lib/files/thumbnails.js'
  import { downloadUrl } from '../../lib/files/preview.js'
  import { clampIndex, counterLabel, keyStep, stepIndex, swipeStep } from '../../lib/files/viewerNav.js'
  import { fileSize } from '../../lib/format.js'

  const NAV_ICON_SIZE = 22
  const FAILED = 'failed'

  let { images = [], index = $bindable(0), onClose } = $props()

  let urls = $state({})
  let pointerStart = null
  let swiped = false

  const position = $derived(clampIndex(index, images.length))
  const image = $derived(images[position])
  const several = $derived(images.length > 1)
  const subtitle = $derived([several ? counterLabel(position, images.length) : '', image ? fileSize(image.size) : ''].filter(Boolean).join(' · '))
  const shown = $derived(image ? urls[image.id] || thumbnails.peek(image.id) : '')

  function remember(id, value) {
    urls = { ...urls, [id]: value }
  }

  $effect(() => {
    const file = image
    if (!file) return
    thumbnails.get(file).then(url => remember(file.id, url), () => remember(file.id, FAILED))
  })

  function go(delta) {
    index = stepIndex(position, delta, images.length)
  }

  function onKey(event) {
    const delta = keyStep(event.key)
    if (!delta) return
    event.preventDefault()
    go(delta)
  }

  function startSwipe(event) {
    pointerStart = { x: event.clientX, y: event.clientY }
  }

  function endSwipe(event) {
    if (!pointerStart) return
    const delta = swipeStep(event.clientX - pointerStart.x, event.clientY - pointerStart.y)
    pointerStart = null
    swiped = Boolean(delta)
    if (delta) go(delta)
  }

  // A tap on the dark area around the picture closes, like the backdrop; the click that ends a swipe doesn't.
  function closeOutsidePicture(event) {
    const tappedBackdrop = event.target === event.currentTarget && !swiped
    swiped = false
    if (tappedBackdrop) onClose()
  }
</script>

<svelte:window onkeydown={onKey} />

{#if image}
  <ViewerShell title={image.name} {subtitle} label={`Picture viewer: ${image.name}`} downloadHref={downloadUrl(image.id)} {onClose}>
    <div class="frame" role="presentation" onclick={closeOutsidePicture} onpointerdown={startSwipe} onpointerup={endSwipe} onpointercancel={() => { pointerStart = null }}>
      {#if shown === FAILED}
        <p class="note" role="alert">This picture can’t be shown here. Download the original instead.</p>
      {:else if shown}
        <img src={shown} alt={image.name} draggable="false" onerror={() => remember(image.id, FAILED)} />
      {:else}
        <span class="spinner" role="status" aria-label="Loading picture"></span>
      {/if}
    </div>
    {#if several}
      <button type="button" class="viewer-control nav previous" aria-label="Previous picture" disabled={position === 0} onclick={() => go(-1)}><Icon name="back" size={NAV_ICON_SIZE} /></button>
      <button type="button" class="viewer-control nav next" aria-label="Next picture" disabled={position === images.length - 1} onclick={() => go(1)}><Icon name="chevron" size={NAV_ICON_SIZE} /></button>
    {/if}
  </ViewerShell>
{/if}

<style>
  .frame {
    display: flex; align-items: center; justify-content: center;
    width: 100%; height: 100%; min-height: 0;
    touch-action: pan-y pinch-zoom; user-select: none;
  }
  img { display: block; max-width: 100%; max-height: 100%; object-fit: contain; border-radius: var(--radius-item); }
  .note { max-width: 320px; color: var(--on-viewer-2); text-align: center; }
  /* Drawn over the picture on phones, so it needs a dark disc to show on light pictures. */
  .nav { position: absolute; top: 50%; transform: translateY(-50%); }
  .nav.viewer-control { background: var(--thumb-overlay); }
  .nav:disabled { visibility: hidden; }
  .previous { left: 16px; }
  .next { right: 16px; }
  .spinner {
    width: 28px; height: 28px;
    border: 2px solid var(--viewer-control-hover); border-top-color: var(--on-viewer); border-radius: var(--radius-pill);
    animation: spin .8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (max-width: 520px) {
    .previous { left: 8px; }
    .next { right: 8px; }
  }
</style>
