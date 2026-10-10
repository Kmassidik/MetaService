<script>
  /** A file's versions (pick which one the list shows) and its technical details. */
  import ViewerShell from './ViewerShell.svelte'
  import { downloadUrl } from '../../lib/files/preview.js'
  import { fileSize } from '../../lib/format.js'

  let { group, file, botName, onPickVersion, onClose } = $props()

  const details = $derived([
    ['Type', file.mediaType || 'Type not detected'],
    ['Size', fileSize(file.size)],
    ['Status', file.state],
    ['Saved', new Date(file.createdAt).toLocaleString()],
    ['Source bot', `${botName(file.agentId)} · ${file.agentId || 'unknown'}`],
    ['File ID', file.id],
    ['SHA-256', file.sha256],
    ['Artifact', file.artifactId],
    ['Source version file', file.sourceFileId],
  ].filter(([, value]) => value))

  function versionLabel(item) {
    return `Version ${item.version ?? 'original'} · ${new Date(item.createdAt).toLocaleString()}`
  }
</script>

<ViewerShell variant="document" title={file.name} subtitle="Details" downloadHref={file.state === 'ready' ? downloadUrl(file.id) : ''} {onClose}>
  {#if group.items.length > 1}
    <fieldset class="versions">
      <legend>Versions</legend>
      {#each group.items as item (item.id)}
        <label class="version">
          <input type="radio" name={`versions-${group.id}`} value={item.id} checked={item.id === file.id} onchange={() => onPickVersion(item.id)} />
          <span>{versionLabel(item)}</span>
        </label>
      {/each}
    </fieldset>
  {/if}
  <dl class="details">
    {#each details as [term, value] (term)}
      <dt>{term}</dt><dd>{value}</dd>
    {/each}
  </dl>
</ViewerShell>

<style>
  .versions { display: grid; gap: 4px; margin: 0 0 18px; padding: 0; border: 0; }
  legend { margin-bottom: 6px; color: var(--text-2); font: 500 12.5px/1.4 var(--font); }
  .version { display: flex; align-items: center; gap: 10px; min-height: 40px; padding: 0 10px; border-radius: var(--radius-control); font: 400 var(--fs-preview)/1.4 var(--font); cursor: pointer; }
  .version:hover { background: var(--row-hover); }
  .version input { accent-color: var(--text); }
  .details { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 16px; margin: 0; font: 13px/1.5 var(--font); }
  dt { color: var(--text-2); }
  dd { margin: 0; overflow-wrap: anywhere; }
  @media (max-width: 520px) {
    .details { grid-template-columns: 1fr; gap: 2px; }
    dd { margin-bottom: 8px; }
  }
</style>
