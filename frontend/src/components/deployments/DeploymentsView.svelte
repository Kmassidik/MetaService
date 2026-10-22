<script module lang="ts">
  type ViewId = 'building' | 'table' | 'cards'

  /** The view picked last stays picked while the panel is open (kept in memory: the panel stores nothing in the browser). */
  let lastView: ViewId = 'building'
</script>

<script lang="ts">
  // The deployments of one machine, laid out like the MAAS Infrastructure page: capacity bars, then the VMs as a building, a table or cards.
  import Building from '../Building.svelte'
  import Owl from '../Owl.svelte'
  import CopyAddress from '../vms/CopyAddress.svelte'
  import TerminalButton from '../vms/TerminalButton.svelte'
  import VmActions from '../vms/VmActions.svelte'
  import GpuBadge from '../GpuBadge.svelte'
  import WhyStopped from '../vm/WhyStopped.svelte'
  import { isPlainMode, PLAIN_MODE_TEXT, readStoppedReason, reasonNote } from '../../lib/stoppedReason.ts'
  import { bundleFlag, formatGb, formatMb } from '../../lib/format.ts'
  import { hostFor, vmServers } from '../../lib/deployments.ts'
  import { vmHref } from '../../lib/routes.ts'
  import type { VmActionHandlers } from '../../lib/vmActions.ts'
  import type { BuildingServer } from '../../lib/building.ts'
  import type { Machine, Workload } from '../../lib/types.ts'

  interface Props {
    machine: Machine
    pinned: string | null | undefined
    /** How many VMs of this machine are being made right now: the empty message must not show while one is. */
    making: number
    onCreate: () => void
    onAct: (machine: Machine, workload: Workload, action: 'start' | 'stop') => Promise<void>
    onDelete: (machine: Machine, workload: Workload) => void
    onInstall: (machine: Machine, workload: Workload | null) => Promise<unknown>
    onOpenChat: (machine: Machine, workload: Workload | null) => void
  }

  let { machine, pinned, making, onCreate, onAct, onDelete, onInstall, onOpenChat }: Props = $props()
  const handlers: VmActionHandlers = $derived({ onAct, onInstall, onOpenChat, onDelete })
  const MAKING_TEXT = 'The first VM is being made. It will be listed here when the machine reports it.'
  const NONE_TEXT = 'No VMs on this machine yet.'
  const VIEWS: [ViewId, string][] = [['building', 'Building'], ['table', 'Table'], ['cards', 'Cards']]
  let view = $state(lastView)
  const servers = $derived(vmServers(machine))
  const host = $derived(hostFor(machine))
  const running = $derived(servers.filter((server) => server.status === 'running').length)
  /** Every server was made from one of the machine's workloads, so this always finds it. */
  function workloadOf(server: BuildingServer): Workload {
    const found = machine.workloads.find((workload) => workload.id === server.id)
    if (!found) throw new Error(`no workload for server ${server.id}`)
    return found
  }

  /** Why a VM stopped, when the machine said why: shown small under its state in the table and the cards. */
  const noteOf = (workload: Workload) => reasonNote(readStoppedReason(workload.stopped_reason))

  function setView(next: ViewId) {
    view = next
    lastView = next
  }
</script>

{#snippet actions(vmId: string)}
  {@const workload = machine.workloads.find((entry) => entry.id === vmId)}
  {#if workload}<TerminalButton {machine} {workload} />{/if}
{/snippet}

<div class="bar-row">
  <span class="runs">{running}/{servers.length} running</span>
  <div class="segmented" role="group" aria-label="View">
    {#each VIEWS as [id, label] (id)}<button type="button" class:on={view === id} aria-pressed={view === id} onclick={() => setView(id)}>{label}</button>{/each}
  </div>
  <button class="btn green sm" type="button" onclick={onCreate}>＋ New VM</button>
</div>

{#if view === 'building'}
  <Building {servers} {host} {actions} none={making > 0 ? MAKING_TEXT : NONE_TEXT} vmLink={(vmId) => vmHref(machine.id, vmId)} />
{:else if servers.length === 0 && making > 0}
  <p class="muted waiting" role="status">{MAKING_TEXT}</p>
{:else if servers.length === 0}
  <div class="empty" role="status"><Owl name="emptyVms" />No VMs on this machine yet.<button class="btn" type="button" onclick={onCreate}>＋ Create a VM</button></div>
{:else if view === 'cards'}
  <div class="grid">
    {#each servers as server (server.id)}
      {@const workload = workloadOf(server)}
      {@const note = noteOf(workload)}
      <div class="card">
        <div class="ch">
          <div class="row1"><a class="nm" href={vmHref(machine.id, server.id)}>{server.display}</a><span class="id">{server.id}</span><span class="tag {server.cls}">{server.status}</span>{#if server.gpu}<GpuBadge />{/if}</div>
          <div class="specs"><span>{server.cpu} vCPU</span><span>{formatMb(server.mem_mb)}</span><span>{formatGb(server.disk_gb)}</span><span>{workload.kind}</span></div>
          <div class="dom">{workload.address ?? 'no address yet'} · {bundleFlag(workload.bundle_version, pinned).text}</div>
          {#if note}<WhyStopped {note} compact />{/if}
          {#if isPlainMode(workload)}<small class="plain">{PLAIN_MODE_TEXT}</small>{/if}
        </div>
        <div class="acts"><VmActions {machine} {workload} {handlers} /></div>
      </div>
    {/each}
  </div>
{:else}
  <div class="tablewrap">
    <table class="restable stack">
      <thead><tr><th>Name</th><th>Status</th><th>Ruvio</th><th>Type</th><th>Size</th><th>Address</th><th></th></tr></thead>
      <tbody>
        {#each servers as server (server.id)}
          {@const workload = workloadOf(server)}
          {@const note = noteOf(workload)}
          <tr>
            <td class="c-name" data-label="Name"><a href={vmHref(machine.id, server.id)}>{server.display}</a><small class="vm-id mono">{server.id}</small></td>
            <td data-label="Status">
              <span class="tag {server.cls}">{server.status}</span>{#if server.gpu}<GpuBadge />{/if}
              {#if note}<WhyStopped {note} compact />{/if}
              {#if isPlainMode(workload)}<small class="plain">{PLAIN_MODE_TEXT}</small>{/if}
            </td>
            <td class="mono" data-label="Ruvio">{bundleFlag(workload.bundle_version, pinned).text}</td>
            <td class="mono" data-label="Type">{workload.kind}</td>
            <td class="mono nums" data-label="Size">{server.cpu}c · {formatMb(server.mem_mb)} · {formatGb(server.disk_gb)}</td>
            <td class="mono muted" data-label="Address"><span class="addr">{workload.address ?? '—'}{#if workload.address}<CopyAddress address={workload.address} />{/if}</span></td>
            <td data-label="Actions"><VmActions {machine} {workload} {handlers} /></td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<style>
  .bar-row { display: flex; align-items: center; justify-content: flex-end; gap: 12px; padding: 12px 0; flex-wrap: wrap; }
  .waiting { margin: 0; padding: 12px 0; font-size: 13px; }
  .plain { display: block; max-width: 280px; font-size: 11px; color: var(--m60); }
  .vm-id { display: block; margin-top: 2px; font-size: 11px; font-weight: 400; color: var(--m50); }
  .addr { display: inline-flex; align-items: center; gap: 8px; }
  .runs { margin-right: auto; font-family: var(--mono); font-size: 12px; color: var(--m50); }
</style>
