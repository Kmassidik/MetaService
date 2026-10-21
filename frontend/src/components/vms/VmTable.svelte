<script lang="ts">
  // The VMs of every machine in one table. Each row opens the VM's own page; the machine name opens the machine's page.
  import GpuBadge from '../GpuBadge.svelte'
  import StatePill from '../StatePill.svelte'
  import TerminalButton from './TerminalButton.svelte'
  import { formatGb, formatMb } from '../../lib/format.ts'
  import { machineHref, vmHref } from '../../lib/routes.ts'
  import { vmTone, type VmRow } from '../../lib/vmList.ts'

  let { rows }: { rows: VmRow[] } = $props()
</script>

<div class="tablewrap">
  <table class="restable" aria-label="VMs">
    <thead><tr><th>Name</th><th>Machine</th><th>Kind</th><th>State</th><th>vCPU</th><th>RAM</th><th>Disk</th><th><span class="sr">Actions</span></th></tr></thead>
    <tbody>
      {#each rows as row (`${row.machineId}/${row.id}`)}
        <tr class:offline={row.machineState === 'offline'}>
          <td class="c-name name" data-label="Name"><a class="open" href={vmHref(row.machineId, row.id)}>{row.name}</a></td>
          <td class="machine" data-label="Machine">
            <a href={machineHref(row.machineId)}>{row.machineName}</a>
            {#if row.machineState !== 'online'}<StatePill state={row.machineState} />{/if}
          </td>
          <td class="mono" data-label="Kind">{row.kind}{#if row.gpu}<GpuBadge />{/if}</td>
          <td data-label="State"><StatePill state={vmTone(row.state)} label={row.state} /></td>
          <td class="mono nums" data-label="vCPU">{row.cpu}</td>
          <td class="mono nums" data-label="RAM">{formatMb(row.ramMb)}</td>
          <td class="mono nums" data-label="Disk">{formatGb(row.diskGb)}</td>
          <td class="act" data-label="Terminal"><TerminalButton machine={{ id: row.machineId, os: row.machineOs, state: row.machineState }} workload={{ id: row.id, name: row.name, state: row.state }} /></td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  tr { position: relative; }
  tbody tr:hover { background: var(--gray2); }
  tr.offline { opacity: 0.7; }
  .name, .machine { overflow-wrap: anywhere; }
  /* The whole row is the link to the VM; the machine link sits above it. */
  .open::after { content: ''; position: absolute; inset: 0; }
  .machine a { position: relative; z-index: 1; }
  .machine :global(.tag) { margin-left: 8px; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  @media (max-width: 820px) {
    thead { display: none; }
    tbody tr { display: block; padding: 12px 0; border-bottom: 1px solid var(--gray); }
    tbody td { display: flex; gap: 8px; align-items: center; padding: 3px 0; border: 0; }
    tbody td::before { content: attr(data-label); flex: 0 0 64px; color: var(--m50); font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em; }
    .machine { display: flex; }
  }
</style>
