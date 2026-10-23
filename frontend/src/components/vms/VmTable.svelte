<script lang="ts">
  // The VMs of every machine in one table. Each row opens the VM's own page; the machine name opens the machine's page.
  import GpuBadge from '../GpuBadge.svelte'
  import StatePill from '../StatePill.svelte'
  import VmActions from './VmActions.svelte'
  import AppChip from '../vm/AppChip.svelte'
  import WhyStopped from '../vm/WhyStopped.svelte'
  import { PLAIN_MODE_TEXT } from '../../lib/stoppedReason.ts'
  import { formatGb, formatMb } from '../../lib/format.ts'
  import { machineHref, vmHref } from '../../lib/routes.ts'
  import type { VmActionHandlers } from '../../lib/vmActions.ts'
  import { findVm, vmTone, type VmRow } from '../../lib/vmList.ts'
  import type { Machine } from '../../lib/types.ts'

  let { rows, machines, handlers }: { rows: VmRow[]; machines: Machine[]; handlers: VmActionHandlers } = $props()
</script>

<div class="tablewrap">
  <table class="restable stack" aria-label="VMs">
    <thead><tr><th>Name</th><th>Machine</th><th>Kind</th><th>State</th><th>vCPU</th><th>RAM</th><th>Disk</th><th><span class="sr">Actions</span></th></tr></thead>
    <tbody>
      {#each rows as row (`${row.machineId}/${row.id}`)}
        {@const vm = findVm(machines, row)}
        <tr class:offline={row.machineState === 'offline'}>
          <td class="c-name name" data-label="Name"><a class="open" href={vmHref(row.machineId, row.id)}>{row.name}</a><small class="vm-id mono">{row.id}</small></td>
          <td class="machine" data-label="Machine">
            <a href={machineHref(row.machineId)}>{row.machineName}</a>
            {#if row.machineState !== 'online'}<StatePill state={row.machineState} />{/if}
          </td>
          <td class="mono" data-label="Kind">{row.kind}{#if row.gpu}<GpuBadge />{/if}</td>
          <td data-label="State">
            <div class="state">
              <StatePill state={vmTone(row.state)} label={row.state} />
              {#if row.app}<AppChip chip={row.app} />{/if}
              {#if row.note}<WhyStopped note={row.note} compact />{/if}
              {#if row.plain}<small class="plain">{PLAIN_MODE_TEXT}</small>{/if}
            </div>
          </td>
          <td class="mono nums" data-label="vCPU">{row.cpu}</td>
          <td class="mono nums" data-label="RAM">{formatMb(row.ramMb)}</td>
          <td class="mono nums" data-label="Disk">{formatGb(row.diskGb)}</td>
          <td class="act" data-label="Actions">{#if vm}<VmActions machine={vm.machine} workload={vm.workload} {handlers} />{/if}</td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  tr { position: relative; }
  tbody tr:hover { background: var(--surface-2); }
  tr.offline { opacity: 0.7; }
  .vm-id { display: block; margin-top: 2px; font-size: 11px; font-weight: 400; color: var(--m50); }
  .name, .machine { overflow-wrap: anywhere; }
  .state { display: grid; justify-items: start; gap: 2px; max-width: 280px; }
  .plain { font-size: 11px; color: var(--m60); }
  /* The whole row is the link to the VM; the machine link sits above it. */
  .open::after { content: ''; position: absolute; inset: 0; }
  .machine a { position: relative; z-index: 1; }
  .machine :global(.tag) { margin-left: 8px; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  @media (max-width: 820px) {
    .machine { display: flex; }
  }
</style>
