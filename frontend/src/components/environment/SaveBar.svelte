<script lang="ts">
  // The bar at the bottom of the Environment tab: it sticks to the bottom of the screen while there are unsaved changes (and for the
  // moment the answer to Save is shown), so nobody has to scroll down to find Save.
  import ActionButton from '../ActionButton.svelte'
  import type { ActionState } from '../../lib/action.svelte.ts'

  interface Props {
    action: ActionState
    canSave: boolean
    onSave: () => Promise<unknown>
    onUndo: () => void
  }

  let { action, canSave, onSave, onUndo }: Props = $props()
</script>

<div class="savebar" role="group" aria-label="Save bar">
  <span class="state">Unsaved changes</span>
  <ActionButton label="Save" busyLabel="Saving…" doneLabel="Saved" variant="green" disabled={!canSave} {action} onrun={onSave} />
  <button class="btn" type="button" disabled={action.busy} onclick={onUndo}>Undo</button>
  <span class="apply">Changes apply to new VMs only.</span>
</div>

<style>
  /* It is itself the grid item of the tab, so it can stick to the bottom of the whole tab and span both columns. */
  .savebar { grid-column: 1 / -1; position: sticky; bottom: 0; z-index: 5; display: flex; align-items: center; gap: 14px; flex-wrap: wrap; padding: 12px 0; border-top: 1px solid var(--line); background: var(--surface); }
  .state { font: 700 12px var(--mono); }
  .apply { font-size: 12.5px; color: var(--m60); }
</style>
