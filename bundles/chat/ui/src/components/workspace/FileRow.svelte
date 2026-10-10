<script>
  /** One file in the Files tab: picture or type icon, name, size and date; ⋯ for everything else. */
  import Icon from '../Icon.svelte'
  import Thumbnail from '../files/Thumbnail.svelte'
  import { fileIcon, isViewableImage } from '../../lib/files/preview.js'
  import { fileMeta } from '../../lib/files/fileList.js'
  import { ICON_SIZE } from '../../lib/constants.js'

  let { file, versionCount = 1, confirming = false, deleting = '', onOpen, onMenu, onDelete, onKeep } = $props()
</script>

<li class="file-row">
  <div class="line">
    <button type="button" class="open" onclick={onOpen}>
      <span class="preview">
        {#if isViewableImage(file)}
          <Thumbnail {file} alt="" />
        {:else}
          <Icon name={fileIcon(file)} size={ICON_SIZE.list} />
        {/if}
      </span>
      <span class="text">
        <strong>{file.name}</strong>
        <small>{fileMeta(file, versionCount)}</small>
      </span>
    </button>
    <button type="button" class="icon-button" aria-label={`Actions for ${file.name}`} aria-haspopup="menu" onclick={onMenu}><Icon name="more" size={ICON_SIZE.header} /></button>
  </div>
  {#if confirming}
    <div class="confirm" role="group" aria-label={`Delete ${file.name}`}>
      <p>Delete this version for good? Messages that use it will no longer download it.</p>
      <div class="file-actions">
        <button type="button" class="danger-button" disabled={Boolean(deleting)} onclick={onDelete}>{deleting === file.id ? 'Deleting…' : 'Delete'}</button>
        <button type="button" class="secondary-button" disabled={Boolean(deleting)} onclick={onKeep}>Keep file</button>
      </div>
    </div>
  {/if}
</li>

<style>
  .file-row { border-radius: var(--radius-control); }
  .line { display: flex; align-items: center; gap: 4px; }
  .open {
    display: flex; flex: 1; align-items: center; gap: 12px; min-width: 0;
    padding: 8px; border-radius: var(--radius-control); background: none; text-align: left;
  }
  .open:hover { background: var(--row-hover); }
  .preview {
    display: grid; place-items: center; flex-shrink: 0; overflow: hidden;
    width: 44px; height: 44px; border-radius: var(--radius-item);
    background: var(--bubble); color: var(--text-2);
  }
  .text { display: grid; min-width: 0; }
  strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text); font: 500 var(--fs-name)/1.35 var(--font); }
  small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-2); font: 400 12.5px/1.4 var(--font); }
  .confirm { margin: 2px 8px 10px 64px; padding: 12px; border: 1px solid var(--danger-line); border-radius: var(--radius-control); background: var(--danger-bg); font: 400 13px/1.45 var(--font); }
  .confirm .file-actions { margin-top: 10px; }
  .confirm .danger-button { min-height: 34px; padding: 6px 14px; font-size: 13px; }
  @media (max-width: 520px) {
    .confirm { margin-left: 8px; }
  }
</style>
