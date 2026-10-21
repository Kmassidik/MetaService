<script lang="ts">
  // What the machine is: its problems with the fix, the GPU note, the plain facts (ID, address, system, CPU, memory, disk, GPU, last seen) and what it can run.
  import SoftwareSection from './SoftwareSection.svelte'
  import GpuToolkitNote from '../GpuToolkitNote.svelte'
  import { canRunText, factRows } from '../../lib/environment.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine, now }: { machine: Machine; now: number } = $props()
  const rows = $derived(factRows(machine, now))
</script>

{#if machine.problems?.length}
  <div class="op-alerts flush" role="alert">
    {#each machine.problems as problem (problem.code)}<div class="op-alert"><b>{problem.message}</b><p>{problem.fix}</p></div>{/each}
  </div>
{/if}
<GpuToolkitNote {machine} />
<SoftwareSection title="This machine" {rows} />
<p class="can">{canRunText(machine.capabilities)}</p>

<style>
  .can { margin: -18px 0 32px; font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .flush { padding-left: 0; padding-right: 0; margin-left: 0; }
</style>
