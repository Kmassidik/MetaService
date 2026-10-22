<script lang="ts">
  // The Helper row of the Software block: which build of the helper program runs, whether the parent has a newer one, and the button that puts it there.
  import { UPDATE_BUTTON, UPDATE_EXPLANATION, UPDATING_TEXT, type HelperView, type OutcomeView } from '../../lib/helperUpdate.ts'

  let { helper, updating, outcome, onUpdate }: { helper: HelperView; updating: boolean; outcome: OutcomeView | null; onUpdate: () => void } = $props()

  const TAGS: Record<HelperView['status'], string> = { up_to_date: 'tag run', available: 'tag warn', unknown: 'tag', cannot: 'tag' }
</script>

<div class="helper">
  <dt>Helper</dt>
  <dd>
    <span class="build" aria-label="Helper build">{helper.build}</span>
    <span class={TAGS[helper.status]} data-helper-status={helper.status}>{helper.label}</span>
    <button class="btn line sm" type="button" disabled={!helper.canUpdate || updating} aria-busy={updating} onclick={onUpdate}>{updating ? UPDATING_TEXT : UPDATE_BUTTON}</button>
  </dd>
  <p class="explain">{UPDATE_EXPLANATION}</p>
  {#if helper.note}<p class="note">{helper.note}</p>{/if}
  {#if outcome}
    <p class="outcome {outcome.tone}" role={outcome.tone === 'bad' ? 'alert' : 'status'}><b>{outcome.title}.</b> {outcome.detail}</p>
  {/if}
</div>

<style>
  .helper { display: grid; grid-template-columns: 160px 1fr; align-items: center; gap: 8px 16px; border-bottom: 1px solid var(--surface-2); padding: 10px 0; }
  .helper dt { font: 11px var(--mono); text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .helper dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; overflow-wrap: anywhere; font-size: 13px; }
  .build { font-family: var(--mono); }
  .explain, .note, .outcome { grid-column: 2; margin: 0; font-size: 12.5px; overflow-wrap: anywhere; }
  .explain { color: var(--m60); }
  .note { color: var(--warn); }
  .outcome { padding: 10px 12px; border: 1px solid; border-left-width: 4px; font-size: 13px; }
  .outcome.ok { border-color: var(--ok-note-line); border-left-color: var(--ok); background: var(--ok-note-bg); color: var(--ok-note-text); }
  .outcome.warn { border-color: var(--warn-note-line); border-left-color: var(--warn-line); background: var(--warn-note-bg); color: var(--warn-note-title); }
  .outcome.bad { border-color: var(--danger-note-line); border-left-color: var(--danger-note-bar); background: var(--danger-note-bg); color: var(--danger-note-text); }
  @media (max-width: 820px) { .helper { grid-template-columns: 1fr; gap: 4px; } .explain, .note, .outcome { grid-column: 1; } }
</style>
