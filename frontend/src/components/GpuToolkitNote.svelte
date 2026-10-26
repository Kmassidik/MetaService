<script lang="ts">
  // On a machine that has an NVIDIA card but not NVIDIA's container toolkit: why containers cannot use the GPU yet, and how to fix it. Nothing here blocks the machine (it still makes VMs and containers).
  import { toolkitNote } from '../lib/gpuChoice.ts'
  import type { Machine } from '../lib/types.ts'

  let { machine }: { machine: Machine } = $props()
  const note = $derived(toolkitNote(machine))
</script>

{#if note}
  <div class="op-alerts" role="status" data-gpu-note="machine">
    <div class="op-alert"><b>{note.title}</b><p>{note.fix}</p></div>
  </div>
{/if}

<style>
  p { overflow-wrap: anywhere; }
</style>
