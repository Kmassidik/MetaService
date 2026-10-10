<script>
  /** A non-picture attachment in a message: type icon, name (opens Files), size and Download. */
  import Icon from '../Icon.svelte'
  import { downloadUrl, fileIcon, isDeleted, isReady } from '../../lib/files/preview.js'
  import { fileSize } from '../../lib/format.js'

  const TYPE_ICON_SIZE = 18
  const ACTION_ICON_SIZE = 17

  let { file, onViewResults } = $props()

  const meta = $derived(isDeleted(file) ? 'This file has been deleted.' : [fileSize(file.size), file.version ? `Version ${file.version}` : ''].filter(Boolean).join(' · '))
</script>

<div class="file-chip" class:deleted={isDeleted(file)}>
  <span class="type"><Icon name={fileIcon(file)} size={TYPE_ICON_SIZE} /></span>
  <button type="button" class="name" title="Show in Files" disabled={isDeleted(file)} onclick={onViewResults}>
    <strong>{file.name}</strong>
    <small>{meta}</small>
  </button>
  {#if isReady(file)}
    <a class="download" href={downloadUrl(file.id)} download aria-label={`Download ${file.name}`} title="Download"><Icon name="download" size={ACTION_ICON_SIZE} /></a>
  {/if}
</div>

<style>
  .file-chip {
    display: flex; align-items: center; gap: 10px;
    width: min(320px, 100%); padding: 8px 8px 8px 10px;
    border: 1px solid var(--hairline); border-radius: var(--radius-card);
    background: var(--surface);
  }
  .type {
    display: grid; place-items: center; flex-shrink: 0;
    width: 36px; height: 36px; border-radius: var(--radius-control);
    background: var(--bubble); color: var(--text-2);
  }
  .name { display: grid; flex: 1; min-width: 0; padding: 0; background: none; text-align: left; }
  .name:disabled { opacity: 1; }
  strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text); font: 500 var(--fs-preview)/1.3 var(--font); }
  small { color: var(--text-2); font: 400 12px/1.35 var(--font); }
  .deleted strong { color: var(--text-2); }
  .download {
    display: grid; place-items: center; flex-shrink: 0;
    width: 34px; height: 34px; border-radius: var(--radius-pill); color: var(--text-2);
  }
  .download:hover { background: var(--row-hover); color: var(--text); }
</style>
