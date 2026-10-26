<script lang="ts">
  // What is wrong with the machine, with the fix, and the GPU note. It stays above the tabs so a problem is never hidden in a closed row or on another tab.
  // A problem the check itself covers gets "Check again" (the same rows and Install it for me offers); one it does not cover gets no button at all.
  // The button is busy while the check dialog opens: a second press starts nothing.
  import GpuToolkitNote from '../GpuToolkitNote.svelte'
  import { actionLabel } from '../../lib/action.ts'
  import { ActionState } from '../../lib/action.svelte.ts'
  import { problemHasCheck } from '../../lib/recheck.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine, onCheck }: { machine: Machine; onCheck: () => void } = $props()
  const checking = new ActionState()
  const label = $derived(actionLabel(checking.view, 'Check again', 'Opening…'))

  function startCheck() {
    void checking.run(async () => onCheck())
  }
</script>

{#if machine.problems?.length}
  <div class="op-alerts" role="alert">
    {#each machine.problems as problem (problem.code)}
      <div class="op-alert">
        <b>{problem.message}</b>
        <p>{problem.fix}</p>
        {#if problemHasCheck(problem)}<button class="btn line sm" type="button" disabled={checking.busy} aria-busy={checking.busy} onclick={startCheck}>{label}</button>{/if}
      </div>
    {/each}
  </div>
{/if}
<GpuToolkitNote {machine} />

<style>
  .op-alert :global(.btn) { margin-top: 6px; }
</style>
