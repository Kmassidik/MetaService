<script lang="ts">
  // All VMs: every VM and container on every machine, narrowed to one machine by the address (#/vms?machine=<id>).
  import VmTable from '../components/vms/VmTable.svelte'
  import { machineChoices } from '../lib/createVm.ts'
  import { createVmHref, vmsHref } from '../lib/routes.ts'
  import PendingVms from '../components/vms/PendingVms.svelte'
  import { pendingFor, type PendingVm } from '../lib/pendingVms.ts'
  import { filterRows, vmFilterFromRoute, vmRows, vmsHeader } from '../lib/vmList.ts'
  import type { Machine } from '../lib/types.ts'

  let { machines, route, banner, pending }: { machines: Machine[]; route: string; banner: string; pending: PendingVm[] } = $props()
  const allRows = $derived(vmRows(machines))
  const chosen = $derived(vmFilterFromRoute(route, machines))
  const rows = $derived(filterRows(allRows, chosen))
  const making = $derived(pendingFor(pending, chosen))
  const names = $derived(machineChoices(machines))

  /** The choice lives in the address, so a reload or a shared link shows the same table. */
  function choose(event: Event) {
    const select = event.currentTarget
    if (select instanceof HTMLSelectElement) location.hash = vmsHref(select.value || null)
  }
</script>

<div class="phead">
  <h1>All VMs</h1><span class="crumb">Infrastructure › {vmsHeader(rows)}</span>
  <div class="sp"><a class="btn green sm" href={createVmHref(chosen)}>＋ Create VM</a></div>
</div>
{#if banner}<p class="banner" role="status">{banner}</p>{/if}
{#if names.length > 0}
  <div class="filter">
    <label for="vm-machine">Machine</label>
    <select id="vm-machine" value={chosen ?? ''} onchange={choose}>
      <option value="">All machines</option>
      {#each names as entry (entry.id)}<option value={entry.id}>{entry.name}</option>{/each}
    </select>
  </div>
{/if}
<PendingVms pending={making} />
{#if allRows.length === 0 && making.length > 0}
  <p class="muted waiting" role="status">The first VM is being made. It will be listed here when its machine reports it.</p>
{:else if allRows.length === 0}
  <div class="empty" role="status">No VMs yet. Make the first one on any of your machines.<a class="btn green sm" href={createVmHref(null)}>＋ Create VM</a></div>
{:else if rows.length === 0 && making.length > 0}
  <p class="muted waiting" role="status">The VM is being made. It will be listed here when its machine reports it.</p>
{:else if rows.length === 0}
  <div class="empty" role="status">No VMs on this machine.<a class="btn green sm" href={createVmHref(chosen)}>＋ Create VM</a></div>
{:else}
  <VmTable {rows} />
{/if}

<style>
  .waiting { padding: 16px 28px 0; margin: 0; font-size: 13px; }
  .filter { display: flex; align-items: center; gap: 10px; padding: 16px 28px 0; font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  select { min-height: 38px; min-width: 200px; max-width: 100%; padding: 0 10px; border: 1px solid var(--line); background: var(--surface); font-family: var(--mono); font-size: 12px; text-transform: none; letter-spacing: 0; color: var(--text); }
  @media (max-width: 820px) { .filter { padding: 16px 16px 0; } select { flex: 1; min-width: 0; } }
</style>
