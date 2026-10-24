<script lang="ts">
  import Owl from './Owl.svelte'
  import MachineRow from './MachineRow.svelte'
  import type { Machine } from '../lib/types.ts'

  let { machines, now, pinned, onRemove, onRename, onAdd, onChanged }: { machines: Machine[]; now: number; pinned: string | null | undefined; onRemove: (machine: Machine) => void; onRename: (machine: Machine) => void; onAdd: () => void; onChanged: () => void } = $props()
</script>

{#if machines.length === 0}
  <div class="empty stage">
    <Owl name="emptyMachines" />
    No machines yet. Add the first one, and it will show up here.
    <button class="btn green sm" type="button" onclick={onAdd}>＋ Add a machine</button>
  </div>
{:else}
  <section class="grid" aria-label="Machines">
    {#each machines as machine (machine.id)}
      <MachineRow {machine} {now} {pinned} {onRemove} {onRename} {onChanged} />
    {/each}
  </section>
{/if}
