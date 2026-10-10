<script>
  /** What the next message carries: pictures as square tiles (tap to view), other files as chips. */
  import Icon from '../Icon.svelte'
  import AttachmentTile from '../files/AttachmentTile.svelte'
  import ImageViewer from '../files/ImageViewer.svelte'
  import { fileSize } from '../../lib/format.js'
  import { isViewableImage, looksLikeImage } from '../../lib/files/preview.js'

  const CHIP_ICON_SIZE = 15
  const CLOSE_ICON_SIZE = 14
  const CANCELLING = 'Cancelling'
  const CLOSED = -1

  let { files = [], uploads = [], locked = false, onRemove, onCancel } = $props()

  let viewing = $state(CLOSED)
  const images = $derived(files.filter(isViewableImage))
  const otherFiles = $derived(files.filter(file => !isViewableImage(file)))
  // A failed picture upload drops back to a text chip so its error can be read.
  const showsAsTile = upload => looksLikeImage(upload.name) && !upload.error
  const imageUploads = $derived(uploads.filter(showsAsTile))
  const otherUploads = $derived(uploads.filter(upload => !showsAsTile(upload)))

  function cancelLabel(upload) {
    return upload.error ? `Remove ${upload.name}` : `Cancel upload of ${upload.name}`
  }

  function versionNote(file) {
    return file.version ? ` · Version ${file.version}` : ''
  }
</script>

{#if files.length || uploads.length}
  <ul class="attachments" aria-label="Selected attachments">
    {#each images as file, position (file.id)}
      <AttachmentTile {file} removeLabel={`Remove ${file.name} from message`} removeDisabled={locked} onOpen={() => { viewing = position }} onRemove={() => onRemove(file)} />
    {/each}
    {#each imageUploads as upload (upload.token)}
      <AttachmentTile {upload} removeLabel={cancelLabel(upload)} removeDisabled={upload.status === CANCELLING} onRemove={() => onCancel(upload)} />
    {/each}
    {#each otherFiles as file (file.id)}
      <li class="chip">
        <Icon name="attach" size={CHIP_ICON_SIZE} />
        <span><strong>{file.name}</strong><small>{fileSize(file.size)}{versionNote(file)} · Ready</small></span>
        <button type="button" disabled={locked} aria-label={`Remove ${file.name} from message`} onclick={() => onRemove(file)}><Icon name="close" size={CLOSE_ICON_SIZE} /></button>
      </li>
    {/each}
    {#each otherUploads as upload (upload.token)}
      <li class="chip">
        <Icon name="attach" size={CHIP_ICON_SIZE} />
        <span>
          <strong>{upload.name}</strong>
          <small>{upload.status} · {fileSize(upload.received)} / {fileSize(upload.size)}</small>
          <progress value={upload.received} max={upload.size || 1} aria-label={`Upload progress for ${upload.name}`}></progress>
          {#if upload.error}<small class="error" role="alert">{upload.error}</small>{/if}
        </span>
        <button type="button" disabled={upload.status === CANCELLING} aria-label={cancelLabel(upload)} onclick={() => onCancel(upload)}><Icon name="close" size={CLOSE_ICON_SIZE} /></button>
      </li>
    {/each}
  </ul>
{/if}

{#if viewing !== CLOSED}
  <ImageViewer {images} bind:index={viewing} onClose={() => { viewing = CLOSED }} />
{/if}

<style>
  .attachments { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin: 0; padding: 10px 10px 4px; list-style: none; }
  .chip {
    display: flex; align-items: center; gap: 8px; max-width: 100%;
    padding: 6px 6px 6px 10px; border-radius: var(--radius-control);
    background: var(--bubble); color: var(--text-2);
  }
  .chip span { display: grid; min-width: 0; }
  strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text); font: 500 var(--fs-preview)/1.3 var(--font); }
  small { font: 400 12px/1.3 var(--font); }
  .error { color: var(--danger); }
  progress { width: 100%; height: 3px; }
  .chip button {
    display: grid; place-items: center; width: 24px; height: 24px; padding: 0;
    border: 0; border-radius: var(--radius-pill); background: transparent; color: var(--text-2); cursor: pointer;
  }
  .chip button:hover:not(:disabled) { background: var(--row-selected); color: var(--text); }
</style>
