<script lang="ts">
  // What is wrong with the machine, with the fix, and the GPU note. It stays above the tabs so a problem is never hidden in a closed row or on another tab.
  // A problem the check itself covers gets "Check again" (the same rows and Install it for me offers); one it does not cover gets no button at all.
  import GpuToolkitNote from '../GpuToolkitNote.svelte'
  import { problemHasCheck } from '../../lib/recheck.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine, onCheck }: { machine: Machine; onCheck: () => void } = $props()
</script>

{#if machine.problems?.length}
  <div class="op-alerts" role="alert">
    {#each machine.problems as problem (problem.code)}
      <div class="op-alert">
        <b>{problem.message}</b>
        <p>{problem.fix}</p>
        {#if problemHasCheck(problem)}<button class="btn line sm" type="button" onclick={onCheck}>Check again</button>{/if}
      </div>
    {/each}
  </div>
{/if}
<GpuToolkitNote {machine} />

<style>
  .op-alert :global(.btn) { margin-top: 6px; }
</style>
