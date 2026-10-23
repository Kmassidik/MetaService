<script lang="ts">
  // What is wrong with the machine, with the fix, and the GPU note. It stays above the rows so a problem is never hidden in a closed row.
  import GpuToolkitNote from '../GpuToolkitNote.svelte'
  import type { Machine } from '../../lib/types.ts'

  let { machine }: { machine: Machine } = $props()
</script>

{#if machine.problems?.length}
  <div class="op-alerts flush" role="alert">
    {#each machine.problems as problem (problem.code)}<div class="op-alert"><b>{problem.message}</b><p>{problem.fix}</p></div>{/each}
  </div>
{/if}
<GpuToolkitNote {machine} />

<style>
  .flush { padding-left: 0; padding-right: 0; margin-left: 0; }
</style>
