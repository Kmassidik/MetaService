<script lang="ts">
  /** A message's attachments: pictures inline (tap to view), other files as compact chips. */
  import type { ChatFile } from '../../lib/types.ts'
  import ImageGrid from '../files/ImageGrid.svelte'
  import FileChip from '../files/FileChip.svelte'
  import { splitAttachments } from '../../lib/files/imageGrid.ts'

  interface Props {
    items?: ChatFile[]
    onViewResults?: (() => unknown) | undefined
  }

  let { items = [], onViewResults }: Props = $props()

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
