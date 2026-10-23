<script lang="ts">
  // What the machine is: the plain facts (ID, address, system, CPU, memory, disk, GPU, last seen) and what it can run.
  import SoftwareSection from './SoftwareSection.svelte'
  import { canRunText, factRows } from '../../lib/environment.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine, now }: { machine: Machine; now: number } = $props()
  const rows = $derived(factRows(machine, now))
</script>

<SoftwareSection {rows} />
<p class="can">{canRunText(machine.capabilities)}</p>

<style>
  .can { margin: 12px 0 0; font-family: var(--mono); font-size: 12px; color: var(--m60); }
</style>
