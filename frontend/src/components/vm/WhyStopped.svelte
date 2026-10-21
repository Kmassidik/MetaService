<script lang="ts">
  // "Why it stopped": the exit code and the last lines the VM printed, as plain text in a code box with a Copy button, or one sentence when the machine did not say why.
  // The log lines come from inside the VM, so they are only ever shown as text. `compact` folds it into a small "Why it stopped" line for table rows.
  import CopyButton from '../connect/CopyButton.svelte'
  import { exitCodeText, stopNoteText, type StopNote } from '../../lib/stoppedReason.ts'

  let { note, compact = false }: { note: StopNote; compact?: boolean } = $props()
  const copyText = $derived(note.kind === 'reason' ? `${exitCodeText(note.reason.exit_code)}\n${note.reason.log_tail}`.trim() : '')
</script>

{#snippet body()}
  {#if note.kind === 'reason'}
    <p class="said">{exitCodeText(note.reason.exit_code)}</p>
    {#if note.reason.log_tail}
      <div class="codebox"><code aria-label="The last lines the VM printed">{note.reason.log_tail}</code><CopyButton text={copyText} describe="why it stopped" /></div>
    {/if}
  {:else}
    <p class="said">{stopNoteText(note)}</p>
  {/if}
{/snippet}

{#if compact}
  <details class="why compact">
    <summary>Why it stopped</summary>
    {@render body()}
  </details>
{:else}
  <section class="why" aria-label="Why it stopped">
    <p class="lbl">Why it stopped</p>
    {@render body()}
  </section>
{/if}

<style>
  .lbl { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.14em; color: var(--m50); margin: 0 0 8px; }
  .said { margin: 0 0 8px; font-size: 13px; color: var(--m70); }
  .codebox { display: flex; gap: 8px; align-items: flex-start; justify-content: space-between; padding: 6px 8px; border: 1px solid var(--gray); background: var(--white); }
  code { min-width: 0; font-family: var(--mono); font-size: 12px; white-space: pre-wrap; overflow-wrap: anywhere; user-select: all; }
  .compact { margin-top: 4px; font-size: 12px; }
  summary { display: inline-block; padding: 2px 0; color: var(--m70); text-decoration: underline; cursor: pointer; }
  summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
  /* Above the stretched row link of the All VMs table, so a click lands here and not on the row. */
  .compact { position: relative; z-index: 2; }
</style>
