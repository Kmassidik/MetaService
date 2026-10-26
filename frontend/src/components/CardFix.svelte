<script lang="ts">
  // The Fix button of a machine card: the same Check again dialog as the machine page, opened from the list the person is looking at.
  // It shows only for a problem the check covers, never for a machine that is offline or was not added over SSH (lib/recheck.ts decides).
  import { FIX_BUTTON, FIX_EXPLANATION, offersCardFix } from '../lib/recheck.ts'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machine, remote, onCheck }: { machine: Machine; remote: RemoteMachineInfo | null; onCheck: () => void } = $props()
  const offer = $derived(offersCardFix(machine, remote))
</script>

{#if offer}
  <div class="cf" data-card-fix>
    <button class="btn line sm" type="button" title={FIX_EXPLANATION} onclick={onCheck}>{FIX_BUTTON}</button>
  </div>
{/if}

<style>
  .cf { margin-top: 10px; }
</style>
