<script>
  /** A PDF, HTML or CSV file in the viewer: downloaded once (capped per type), then shown on a sheet. */
  import ViewerShell from './ViewerShell.svelte'
  import PdfPreview from './PdfPreview.svelte'
  import HtmlPreview from './HtmlPreview.svelte'
  import CsvPreview from './CsvPreview.svelte'
  import { fetchFileBytes } from '../../lib/files/download.js'
  import { PREVIEW_LABELS, PREVIEW_LIMITS, downloadUrl, previewKind } from '../../lib/files/preview.js'
  import { prepareTextPreview } from '../../lib/files/textPreview.js'
  import { fileSize } from '../../lib/format.js'

  /** `file` is what gets downloaded; `title` names it (a rendered PDF shows its source's name). */
  let { file, title, onClose } = $props()

  const kind = $derived(previewKind(file))
  let pdfData = $state.raw(null)
  let text = $state.raw(null)
  let error = $state('')

  async function load(source, signal) {
    try {
      const sourceKind = previewKind(source)
      const data = await fetchFileBytes(source, PREVIEW_LIMITS[sourceKind], signal)
      if (sourceKind === 'pdf') pdfData = data
      else text = prepareTextPreview(sourceKind, data)
    } catch (failure) {
      if (failure.name !== 'AbortError') error = failure.message
    }
  }

  $effect(() => {
    const controller = new AbortController()
    load(file, controller.signal)
    return () => controller.abort()
  })
</script>

<ViewerShell variant="document" {title} subtitle={`${PREVIEW_LABELS[kind]} preview · ${fileSize(file.size)}`} label={`Preview of ${title}`} downloadHref={downloadUrl(file.id)} {onClose}>
  {#if error}
    <div class="error-box" role="alert">{error}</div>
  {:else if pdfData}
    <PdfPreview data={pdfData} name={title} onError={message => { error = message }} />
  {:else if text && kind === 'html'}
    <HtmlPreview content={text} name={title} />
  {:else if text}
    <CsvPreview content={text} name={title} />
  {:else}
    <p class="file-meta" role="status">Loading preview…</p>
  {/if}
</ViewerShell>
