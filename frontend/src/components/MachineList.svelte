<script>
  import MachineRow from './MachineRow.svelte'

  let { machines, now, pinned, onRemove, onAdd, onAct, onDelete, onInstall, onOpenChat } = $props()
</script>

{#if machines.length === 0}
  <div class="empty">
    No machines yet. Add the first one, then install the Agent on it with the enrollment token you get here.
    <button class="btn green sm" type="button" onclick={onAdd}>＋ Add a machine</button>
  </div>
{:else}
  <section class="grid" aria-label="Machines">
    {#each machines as machine (machine.id)}
      <MachineRow {machine} {now} {pinned} {onRemove} {onAct} {onDelete} {onInstall} {onOpenChat} />
    {/each}
  </section>
{/if}
