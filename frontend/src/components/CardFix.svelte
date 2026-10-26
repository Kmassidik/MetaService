<script lang="ts">
  // The Fix button of a machine card: the same Check again dialog as the machine page, opened from the list the person is looking at.
  // It shows only for a problem the check covers, never for a machine that is offline or was not added over SSH (lib/recheck.ts decides).
  // Pressing it while the dialog is opening does nothing else: one press, one check.
  import { actionLabel } from '../lib/action.ts'
  import { ActionState } from '../lib/action.svelte.ts'
  import { FIX_BUTTON, FIX_EXPLANATION, offersCardFix } from '../lib/recheck.ts'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machine, remote, onCheck }: { machine: Machine; remote: RemoteMachineInfo | null; onCheck: () => void } = $props()
  const offer = $derived(offersCardFix(machine, remote))
  const opening = new ActionState()
  const label = $derived(actionLabel(opening.view, FIX_BUTTON, 'Opening…'))

  function press() {
    void opening.run(async () => onCheck())
  }
</script>

{#if offer}
  <div class="cf" data-card-fix>
    <button class="btn line sm" type="button" title={FIX_EXPLANATION} disabled={opening.busy} aria-busy={opening.busy} onclick={press}>{label}</button>
  </div>
{/if}

<style>
  /* The card puts the button in its own reserved row, so the margin comes from there. */
  .cf { margin-top: 0; }
</style>
