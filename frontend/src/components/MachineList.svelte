<script lang="ts">
  import Owl from './Owl.svelte'
  import MachineRow from './MachineRow.svelte'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machines, remotes, now, pinned, onRemove, onRename, onAdd, onChanged, onCheck }: { machines: Machine[]; remotes: RemoteMachineInfo[]; now: number; pinned: string | null | undefined; onRemove: (machine: Machine) => void; onRename: (machine: Machine) => void; onAdd: () => void; onChanged: () => void; onCheck: (machine: Machine) => void } = $props()
  const remoteOf = (machine: Machine) => remotes.find((info) => info.machine === machine.id) ?? null
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
      <MachineRow {machine} remote={remoteOf(machine)} {now} {pinned} {onRemove} {onRename} {onChanged} {onCheck} />
    {/each}
  </section>
{/if}
