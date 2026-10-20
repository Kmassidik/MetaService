<script lang="ts">
  /** A PDF, HTML or CSV file in the viewer: downloaded once (capped per type), then shown on a sheet. */
  import type { ChatFile } from '../../lib/types.ts'
  import { errorMessage, errorName } from '../../lib/errors.ts'
  import ViewerShell from './ViewerShell.svelte'
  import PdfPreview from './PdfPreview.svelte'
  import HtmlPreview from './HtmlPreview.svelte'
  import CsvPreview from './CsvPreview.svelte'
  import { fetchFileBytes } from '../../lib/files/download.ts'
  import { PREVIEW_LABELS, PREVIEW_LIMITS, downloadUrl, previewKind } from '../../lib/files/preview.ts'
  import { prepareTextPreview, type TextPreview } from '../../lib/files/textPreview.ts'
  import { fileSize } from '../../lib/format.ts'

  /** `file` is what gets downloaded; `title` names it (a rendered PDF shows its source's name). */
  interface Props {
    file: ChatFile
    title: string
    onClose: () => void
  }

  let { file, title, onClose }: Props = $props()

  const kind = $derived(previewKind(file))
  let pdfData = $state.raw<Uint8Array | null>(null)
  let text = $state.raw<TextPreview | null>(null)
  let error = $state('')

  async function load(source: ChatFile, signal: AbortSignal): Promise<void> {
    try {
      const sourceKind = previewKind(source)
      if (sourceKind === '' || sourceKind === 'image') throw new Error('This file cannot be previewed here.')
      const data = await fetchFileBytes(source, PREVIEW_LIMITS[sourceKind], signal)
      if (sourceKind === 'pdf') pdfData = data
      else text = prepareTextPreview(sourceKind, data)
    } catch (failure) {
      if (errorName(failure) !== 'AbortError') error = errorMessage(failure)
    }
  }

  $effect(() => {
    const controller = new AbortController()
    load(file, controller.signal)
    return () => controller.abort()
  })
</script>

<ViewerShell variant="document" {title} subtitle={`${kind ? PREVIEW_LABELS[kind] : ''} preview · ${fileSize(file.size)}`} label={`Preview of ${title}`} downloadHref={downloadUrl(file.id)} {onClose}>
  {#if error}
    <div class="error-box" role="alert">{error}</div>
  {:else if pdfData}
    <PdfPreview data={pdfData} name={title} onError={message => { error = message }} />
  {:else if text && 'html' in text}
    <HtmlPreview content={text} name={title} />
  {:else if text}
    <CsvPreview content={text} name={title} />
  {:else}
    <p class="file-meta" role="status">Loading preview…</p>
  {/if}
</ViewerShell>
