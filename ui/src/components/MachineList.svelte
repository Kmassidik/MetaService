<script>
  import MachineRow from './MachineRow.svelte'

  let { machines, now, onRemove, onAdd, onAct, onDelete } = $props()
</script>

{#if machines.length === 0}
  <section class="empty">
    <h2>No machines yet</h2>
    <p class="muted">Add the first machine, then install the Agent on it with the enrollment token you get here.</p>
    <button class="btn primary" type="button" onclick={onAdd}>Add a machine</button>
  </section>
{:else}
  <section class="list" aria-label="Machines">
    <div class="head" aria-hidden="true">
      <span>Machine</span><span>Platform</span><span>State</span><span>Memory</span><span>Disk</span><span>Workloads</span><span>Last seen</span><span></span>
    </div>
    {#each machines as machine (machine.id)}
      <MachineRow {machine} {now} {onRemove} {onAct} {onDelete} />
    {/each}
  </section>
{/if}

<style>
  .list {
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    overflow: hidden;
  }
  .head {
    display: grid;
    grid-template-columns: minmax(150px, 1.3fr) minmax(130px, 1fr) 110px minmax(150px, 1.2fr) minmax(150px, 1.2fr) minmax(100px, 0.8fr) 90px 170px;
    gap: 14px;
    padding: 10px 18px;
    background: var(--surface-2);
    color: var(--muted);
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-weight: 600;
  }
  .empty {
    display: grid;
    justify-items: start;
    gap: 12px;
    padding: 32px;
    background: var(--surface);
    border: 1px dashed var(--line);
    border-radius: var(--radius);
  }
  @media (max-width: 900px) {
    .head { display: none; }
    .empty { padding: 22px; }
  }
</style>
