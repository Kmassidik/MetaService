<script>
  /**
   * A PDF drawn page by page on a canvas: no links, scripts or form actions, at most 200 pages,
   * each page bounded to 12 megapixels. Errors go to `onError`; the parent shows them instead.
   */
  import { tick } from 'svelte'
  import { PDF_MAX_PAGES, openPdf, pdfScale } from '../../lib/files/pdfPreview.js'

  const MIN_CANVAS_PX = 1
  const RENDER_CANCELLED = 'RenderingCancelledException'
  const PASSWORD_MESSAGE = 'Password-protected PDFs cannot be previewed here. Download the original.'

  let { data, name, onError } = $props()

  let canvas = $state(null)
  let pdf = $state.raw(null)
  let page = $state(1)
  let pages = $state(0)
  let rendering = $state(false)
  let loadingTask = null
  let renderTask = null
  let closed = false

  function fail(message) {
    if (!closed) onError(message)
  }

  async function open(bytes) {
    try {
      loadingTask = await openPdf(bytes)
      if (closed) return close()
      loadingTask.onPassword = () => fail(PASSWORD_MESSAGE)
      const opened = await loadingTask.promise
      if (opened.numPages > PDF_MAX_PAGES) throw new Error(`PDF preview is limited to ${PDF_MAX_PAGES} pages. Download the original.`)
      if (closed) return
      pdf = opened
      pages = opened.numPages
      await renderPage(1)
    } catch (failure) {
      fail(failure.message)
    }
  }

  async function drawPage(pdfPage) {
    const viewport = pdfPage.getViewport({ scale: pdfScale(pdfPage.getViewport({ scale: 1 })) })
    await tick()
    if (closed || !canvas) return
    canvas.width = Math.max(MIN_CANVAS_PX, Math.floor(viewport.width))
    canvas.height = Math.max(MIN_CANVAS_PX, Math.floor(viewport.height))
    renderTask = pdfPage.render({ canvas, viewport, intent: 'display' })
    await renderTask.promise
  }

  async function renderPage(number) {
    if (!pdf || rendering) return
    rendering = true
    let pdfPage
    try {
      pdfPage = await pdf.getPage(number)
      await drawPage(pdfPage)
      page = number
    } catch (failure) {
      if (failure.name !== RENDER_CANCELLED) fail(`PDF rendering failed: ${failure.message}. Download the original instead.`)
    } finally {
      pdfPage?.cleanup()
      rendering = false
      renderTask = null
    }
  }

  function close() {
    closed = true
    renderTask?.cancel()
    loadingTask?.destroy().catch(error => console.warn('PDF preview cleanup failed', error))
  }

  // `data` is fixed for this preview's life: DocumentPreview mounts a new one per file.
  $effect(() => {
    open(data)
    return close
  })
</script>

<div class="pdf-navigation" role="group" aria-label="PDF pages">
  <button type="button" class="secondary-button" disabled={rendering || page <= 1} onclick={() => renderPage(page - 1)}>Previous</button>
  <span role="status">{pages ? `Page ${page} of ${pages}` : 'Opening PDF…'}{rendering ? ' · Rendering…' : ''}</span>
  <button type="button" class="secondary-button" disabled={rendering || page >= pages} onclick={() => renderPage(page + 1)}>Next</button>
</div>
<canvas bind:this={canvas} class="pdf-canvas" aria-label={`Page ${page} of ${name}`}></canvas>
<p class="file-meta">Canvas preview only; no links, scripts or form actions. Fonts and complex PDF features may differ.</p>

<style>
  .pdf-navigation { display: flex; align-items: center; justify-content: space-between; gap: 8px; font: 12.5px/1.6 var(--font); color: var(--text-2); }
  .pdf-navigation .secondary-button { min-height: 34px; padding: 6px 14px; font-size: 13px; }
  .pdf-canvas { display: block; width: 100%; height: auto; margin-top: 12px; border: 1px solid var(--hairline); background: var(--paper); }
</style>
