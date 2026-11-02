<script lang="ts">
  // What the newest delete, start or stop of a VM is doing or how it ended: the current step while it runs, or the plain reason with a Retry button when it did not
  // finish. Used on the VM row and on the VM page. Retry is only offered for Delete, Start and Stop (never Create); a Delete retry opens the usual confirm window.
  import ActionButton from '../ActionButton.svelte'
  import type { JobLine, RetryType } from '../../lib/jobState.ts'

  let { line, onRetry, center = false }: { line: JobLine | null; onRetry: (type: RetryType) => Promise<unknown> | void; center?: boolean } = $props()
  const RETRY_WORDS: Record<RetryType, { busy: string; done: string }> = {
    delete: { busy: 'Opening…', done: '' },
    start: { busy: 'Starting…', done: 'Started' },
    stop: { busy: 'Stopping…', done: 'Stopped' },
  }
</script>

{#if line}
  <div class="job {line.kind}" class:center data-testid="job-line" data-type={line.type} role="status" aria-live="polite">
    {#if line.kind === 'working'}<span class="btn-spin" aria-hidden="true"></span>{/if}
    <span class="text" data-testid="job-text">{line.text}</span>
    {#if line.retry}
      {@const words = RETRY_WORDS[line.retry]}
      {@const retry = line.retry}
      <ActionButton variant="line" small label="Retry" busyLabel={words.busy} doneLabel={words.done} onrun={async () => onRetry(retry)} />
    {/if}
  </div>
{/if}

<style>
  .job { display: flex; flex-wrap: wrap; align-items: center; justify-content: flex-end; gap: 4px 8px; font-family: var(--mono); font-size: 11px; color: var(--m60); max-width: 320px; }
  .job.stopped { color: var(--danger); }
  .working { flex-wrap: nowrap; align-items: flex-start; }
  .working .btn-spin { margin-top: 2px; flex: none; }
  .text { overflow-wrap: anywhere; min-width: 0; }
  .center { justify-content: flex-start; max-width: none; }
  @media (max-width: 820px) { .job { justify-content: flex-start; } }
</style>
