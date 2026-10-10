<script>
  /** A message's attachments: pictures inline (tap to view), other files as compact chips. */
  import ImageGrid from '../files/ImageGrid.svelte'
  import FileChip from '../files/FileChip.svelte'
  import { splitAttachments } from '../../lib/files/imageGrid.js'

  let { items = [], onViewResults } = $props()

  const parts = $derived(splitAttachments(items))
</script>

{#if items.length}
  <div class="message-files" aria-label="Message files">
    <ImageGrid images={parts.images} />
    {#each parts.others as file (file.id)}
      <FileChip {file} {onViewResults} />
    {/each}
  </div>
{/if}

<style>
  .message-files { display: flex; flex-direction: column; align-items: inherit; gap: 6px; max-width: 100%; }
</style>
