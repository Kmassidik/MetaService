<script>
  /** View / copy the original text behind an HTML or CSV preview. */
  let { source, name } = $props()

  const SOURCE_ROWS = 10

  let open = $state(false)
  let copyStatus = $state('')

  async function copy() {
    try {
      await navigator.clipboard.writeText(source)
      copyStatus = 'Copied source'
    } catch {
      copyStatus = 'Copy failed. Select the source text to copy.'
    }
  }
</script>

<div class="file-actions">
  <button type="button" class="text-button" aria-expanded={open} onclick={() => { open = !open }}>{open ? 'Hide source' : 'View source'}</button>
  <button type="button" class="text-button" onclick={copy}>Copy source</button>
  <span class="file-meta" role="status">{copyStatus}</span>
</div>
{#if open}
  <textarea class="message-source source-review" aria-label={`Original source of ${name}`} readonly rows={SOURCE_ROWS} value={source}></textarea>
{/if}
