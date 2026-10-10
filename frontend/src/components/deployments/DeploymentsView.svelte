<script module>
  /** The view picked last stays picked while the panel is open (kept in memory: the panel stores nothing in the browser). */
  let lastView = 'building'
</script>

<script>
  // The deployments of one machine, laid out like the MAAS Infrastructure page: capacity bars, then the VMs as a building, a table or cards.
  import Building from '../Building.svelte'
  import { bundleFlag, formatGb, formatMb } from '../../lib/format.js'
  import { hostFor, vmServers } from '../../lib/deployments.js'

  let { machine, pinned, onCreate, onAct, onDelete, onInstall, onOpenChat } = $props()
  const VIEWS = [['building', 'Building'], ['table', 'Table'], ['cards', 'Cards']]
  let view = $state(lastView)
  const servers = $derived(vmServers(machine))
  const host = $derived(hostFor(machine))
  const running = $derived(servers.filter((server) => server.status === 'running').length)
  const diskPct = $derived(host.disk_total_gb ? Math.min(100, Math.round((host.disk_alloc_gb / host.disk_total_gb) * 100)) : 0)
  const ramAllocMb = $derived(servers.filter((server) => server.status === 'running').reduce((sum, server) => sum + server.mem_mb, 0))
  const workloadOf = (server) => machine.workloads.find((workload) => workload.id === server.id)

  function setView(next) {
    view = next
    lastView = next
  }
</script>

<div class="caps">
  <div class="m">Disk allocated
    <span class="bar"><i class:hi={diskPct > 85} style:width="{diskPct}%"></i></span>
    <b>{host.disk_alloc_gb} GB</b> / {host.disk_total_gb} GB
  </div>
  <div class="m">{host.disk_free_gb ?? '–'} GB free now <span class="hintnote">· VMs are sparse, so free drops only as they fill</span></div>
  <div class="m">RAM <b>{formatMb(ramAllocMb)}</b> / {formatMb(host.ram_total_mb)} · {servers.length} VM{servers.length === 1 ? '' : 's'}</div>
</div>

<div class="bar-row">
  <span class="runs">{running}/{servers.length} running</span>
  <div class="segmented" role="group" aria-label="View">
    {#each VIEWS as [id, label] (id)}<button type="button" class:on={view === id} aria-pressed={view === id} onclick={() => setView(id)}>{label}</button>{/each}
  </div>
  <button class="btn green sm" type="button" onclick={onCreate}>＋ New VM</button>
</div>

{#if view === 'building'}
  <Building {servers} {host} />
{:else if servers.length === 0}
  <div class="empty" role="status">No VMs on this machine yet.<button class="btn" type="button" onclick={onCreate}>＋ Create a VM</button></div>
{:else if view === 'cards'}
  <div class="grid">
    {#each servers as server (server.id)}
      {@const workload = workloadOf(server)}
      <div class="card">
        <div class="ch">
          <div class="row1"><span class="nm">{server.display}</span><span class="id">{server.id}</span><span class="tag {server.cls}">{server.status}</span></div>
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
            <td class="c-name">{server.display}</td>
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
