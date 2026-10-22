<script lang="ts">
  import ActionButton from './ActionButton.svelte'
  import Dialog from './Dialog.svelte'
  import { ActionState } from '../lib/action.svelte.ts'
  import type { Machine, Workload } from '../lib/types.ts'

  let { target, onCancel, onConfirm }: { target: { machine: Machine; workload: Workload } | null; onCancel: () => void; onConfirm: () => Promise<void> } = $props()
  /** A fresh action each time the dialog is opened for a VM, so an old failure never shows up on the next one. */
  const action = $derived.by(() => {
    void target
    return new ActionState()
  })
</script>

<Dialog open={target !== null} title="Delete this VM?" onClose={onCancel} locked={action.busy}>
  {#if target}
    <p><strong>{target.workload.name}</strong> on <strong>{target.machine.name}</strong> will be stopped and deleted. The machine makes a backup of it first and keeps that backup;
      if the backup fails, nothing is deleted.</p>
    <div class="row">
      {#if action.busy}<span class="still" role="status">Still working. The dialog closes when it is done.</span>{/if}
      <button class="btn line" type="button" disabled={action.busy} onclick={onCancel}>Keep it</button>
      <ActionButton {action} variant="danger" label="Back up and delete" busyLabel="Deleting…" doneLabel="Deleted" onrun={onConfirm} />
    </div>
  {/if}
</Dialog>

<style>
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
  .still { margin-right: auto; align-self: center; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
