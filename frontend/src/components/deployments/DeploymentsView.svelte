<script module lang="ts">
  type ViewId = 'building' | 'table' | 'cards'

  /** The view picked last stays picked while the panel is open (kept in memory: the panel stores nothing in the browser). */
  let lastView: ViewId = 'building'
</script>

<script lang="ts">
  // The deployments of one machine, laid out like the MAAS Infrastructure page: capacity bars, then the VMs as a building, a table or cards.
  import Building from '../Building.svelte'
  import { bundleFlag, formatGb, formatMb } from '../../lib/format.ts'
  import { hostFor, vmServers } from '../../lib/deployments.ts'
  import { vmHref } from '../../lib/routes.ts'
  import type { BuildingServer } from '../../lib/building.ts'
  import type { Machine, Workload } from '../../lib/types.ts'

  interface Props {
    machine: Machine
    pinned: string | null | undefined
    onCreate: () => void
    onAct: (machine: Machine, workload: Workload, action: 'start' | 'stop') => void
    onDelete: (machine: Machine, workload: Workload) => void
    onInstall: (machine: Machine, workload: Workload | null) => void
    onOpenChat: (machine: Machine, workload: Workload | null) => void
  }

  let { machine, pinned, onCreate, onAct, onDelete, onInstall, onOpenChat }: Props = $props()
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

  function setView(next: ViewId) {
    view = next
    lastView = next
  }
</script>

<div class="bar-row">
  <span class="runs">{running}/{servers.length} running</span>
  <div class="segmented" role="group" aria-label="View">
    {#each VIEWS as [id, label] (id)}<button type="button" class:on={view === id} aria-pressed={view === id} onclick={() => setView(id)}>{label}</button>{/each}
  </div>
  <button class="btn green sm" type="button" onclick={onCreate}>＋ New VM</button>
</div>

{#if view === 'building'}
  <Building {servers} {host} vmLink={(vmId) => vmHref(machine.id, vmId)} />
{:else if servers.length === 0}
  <div class="empty" role="status">No VMs on this machine yet.<button class="btn" type="button" onclick={onCreate}>＋ Create a VM</button></div>
{:else if view === 'cards'}
  <div class="grid">
    {#each servers as server (server.id)}
      {@const workload = workloadOf(server)}
      <div class="card">
        <div class="ch">
          <div class="row1"><a class="nm" href={vmHref(machine.id, server.id)}>{server.display}</a><span class="id">{server.id}</span><span class="tag {server.cls}">{server.status}</span></div>
          <div class="specs"><span>{server.cpu} vCPU</span><span>{formatMb(server.mem_mb)}</span><span>{formatGb(server.disk_gb)}</span><span>{workload.kind}</span></div>
          <div class="dom">{workload.address ?? 'no address yet'} · {bundleFlag(workload.bundle_version, pinned).text}</div>
        </div>
        <div class="acts">
          {#if server.status === 'stopped'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'start')}>Start</button>{/if}
          {#if server.status === 'running'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'stop')}>Stop</button>
            <button class="btn line sm" type="button" onclick={() => onInstall(machine, workload)}>{workload.bundle_version ? 'Reinstall chat' : 'Install chat'}</button>{/if}
          {#if workload.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, workload)}>Open chat</button>{/if}
          <button class="btn danger sm del" type="button" onclick={() => onDelete(machine, workload)}>Delete</button>
        </div>
      </div>
    {/each}
  </div>
{:else}
  <div class="tablewrap">
    <table class="restable">
      <thead><tr><th>Name</th><th>ID</th><th>Status</th><th>Ruvio</th><th>Type</th><th>Size</th><th>Address</th><th></th></tr></thead>
      <tbody>
        {#each servers as server (server.id)}
          {@const workload = workloadOf(server)}
          <tr>
            <td class="c-name"><a href={vmHref(machine.id, server.id)}>{server.display}</a></td>
            <td class="mono muted">{server.id}</td>
            <td><span class="tag {server.cls}">{server.status}</span></td>
            <td class="mono">{bundleFlag(workload.bundle_version, pinned).text}</td>
            <td class="mono">{workload.kind}</td>
            <td class="mono nums">{server.cpu}c · {formatMb(server.mem_mb)} · {formatGb(server.disk_gb)}</td>
            <td class="mono muted">{workload.address ?? '—'}</td>
            <td class="row-act">
              {#if server.status === 'running'}<button class="btn line sm" type="button" onclick={() => onInstall(machine, workload)}>{workload.bundle_version ? 'Reinstall chat' : 'Install chat'}</button>{/if}
              {#if workload.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, workload)}>Open chat</button>{/if}
              {#if server.status === 'running'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'stop')}>Stop</button>{/if}
              {#if server.status === 'stopped'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'start')}>Start</button>{/if}
              <button class="btn danger sm" type="button" onclick={() => onDelete(machine, workload)}>Delete</button>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<style>
  .bar-row { display: flex; align-items: center; justify-content: flex-end; gap: 12px; padding: 12px 0; flex-wrap: wrap; }
  .runs { margin-right: auto; font-family: var(--mono); font-size: 12px; color: var(--m50); }
</style>
