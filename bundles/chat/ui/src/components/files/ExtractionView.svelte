<script>
  /**
   * Extracted text (OCR) of a picture or PDF, in the viewer. Starts when it opens; Stop or closing
   * asks the host to cancel. A reserved request ID means even a Stop before the slow call starts
   * reaches the worker.
   */
  import { onDestroy } from 'svelte'
  import ViewerShell from './ViewerShell.svelte'
  import { cancelExtraction, extractedText, readExtraction, reserveExtraction, startExtraction } from '../../lib/files/extraction.js'

  const PAGE_ROWS = 8

  let { file, sessionKey, onClose } = $props()

  let extraction = $state(null)
  let busy = $state(true)
  let stopping = $state(false)
  let error = $state('')
  let status = $state('')
  let copyStatus = $state('')
  const job = { id: '', cancelled: false, settled: false, cancellation: null }

  function requestCancel() {
    if (!job.id || job.settled) return Promise.resolve()
    job.cancellation ||= cancelExtraction(file.id, sessionKey, job.id).catch(failure => {
      job.cancellation = null
      throw failure
    })
    return job.cancellation
  }

  async function failureMessage(failure) {
    if (job.settled) return failure.message
    try {
      await requestCancel()
    } catch {
      return `${failure.message} Worker cancellation could not be confirmed; safety limits still apply.`
    }
    return job.id ? `${failure.message} Cancellation was requested; the worker's final state could not be confirmed.` : failure.message
  }

  async function extract() {
    const response = await startExtraction(file.id, sessionKey, job.id)
    job.settled = true
    extraction = await readExtraction(response)
    if (job.cancelled) status = 'Text extraction finished before cancellation took effect.'
  }

  async function run() {
    try {
      job.id = await reserveExtraction(file.id, sessionKey)
      if (!job.cancelled) return await extract()
      await requestCancel()
      status = 'Text extraction cancelled before it started.'
    } catch (failure) {
      error = await failureMessage(failure)
    } finally {
      job.settled = true
      busy = false
      stopping = false
    }
  }

  async function stop() {
    job.cancelled = true
    stopping = true
    error = ''
    try {
      await requestCancel()
    } catch (failure) {
      stopping = false
      error = `${failure.message} Extraction may still be running; try Stop again.`
    }
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(extractedText(extraction))
      copyStatus = 'Copied'
    } catch {
      copyStatus = 'Copy failed. Select the extracted text to copy.'
    }
  }

  function stopOnClose() {
    job.cancelled = true
    requestCancel().catch(failure => console.warn('Text extraction cancel failed', failure))
  }

  run()
  onDestroy(stopOnClose)
</script>

<ViewerShell variant="document" title={`Text from ${file.name}`} subtitle="Extracted text" {onClose}>
  {#if busy}
    <div class="file-actions">
      <span class="file-meta" role="status">{stopping ? 'Stopping extraction…' : 'Extracting text…'}</span>
      <button type="button" class="secondary-button" disabled={stopping} onclick={stop}>Stop</button>
    </div>
  {/if}
  {#if error}<div class="error-box" role="alert">{error}</div>{/if}
  {#if status}<p class="file-meta" role="status">{status}</p>{/if}
  {#if extraction}
    <section aria-label={`Extracted text of ${file.name}`}>
      <p class="file-meta">{extraction.engine} · Revision {extraction.revision}. OCR may contain errors; verify against the original.</p>
      {#each extraction.warnings || [] as warning (warning)}<p class="file-meta" role="status">{warning}</p>{/each}
      <div class="file-actions">
        <button type="button" class="secondary-button" onclick={copy}>Copy all text</button>
        <span class="file-meta" role="status">{copyStatus}</span>
      </div>
      {#each extraction.pages as page (page.page)}
        <h4>Page {page.page} · {page.source}</h4>
        <textarea class="message-source source-review" aria-label={`Extracted text of ${file.name}, page ${page.page}`} readonly rows={PAGE_ROWS} value={page.text || 'No text detected on this page.'}></textarea>
      {/each}
    </section>
  {/if}
</ViewerShell>

<style>
  h4 { margin: 18px 0 6px; color: var(--text-2); font: 500 12.5px/1.4 var(--font); }
</style>
