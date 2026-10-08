<script>
  import StatePill from './StatePill.svelte'
  import Meter from './Meter.svelte'
  import { archName, formatGb, formatMb, osName, relativeTime } from '../lib/format.js'

  let { machine, now, onRemove } = $props()
  const WORKLOAD_TONE = { running: 'online', stopped: 'offline' }
  let open = $state(false)
  const gpuLabel = (mode) => ({ none: 'no GPU', container: 'GPU in container', passthrough: 'GPU passthrough' })[mode] ?? mode
</script>

<article class="row" class:offline={machine.state === 'offline'}>
  <div class="cell name" data-label="Machine">
    <strong>{machine.name}</strong>
    <span class="mono muted">{machine.ip ?? 'address unknown'}</span>
  </div>
  <div class="cell" data-label="Platform">
    <span>{osName(machine.os)} <span class="tag">{archName(machine.arch)}</span></span>
    <span class="muted nums">{machine.cpu_cores ?? '–'} cores</span>
  </div>
  <div class="cell" data-label="State">
    <StatePill state={machine.state} />
  </div>
  <div class="cell" data-label="Memory">
    <Meter label="Memory" free={machine.free_ram_mb} total={machine.ram_total_mb} format={formatMb} />
  </div>
  <div class="cell" data-label="Disk">
    <Meter label="Disk" free={machine.free_disk_gb} total={machine.disk_total_gb} format={formatGb} />
  </div>
  <div class="cell" data-label="Workloads">
    <span class="nums">{machine.workloads.length} {machine.workloads.length === 1 ? 'workload' : 'workloads'}</span>
    <span class="muted">bundle {machine.bundle_version ?? '–'}</span>
  </div>
  <div class="cell" data-label="Last seen">
    <span class="nums">{relativeTime(machine.last_seen, now)}</span>
  </div>
  <div class="cell actions">
    <button class="btn" type="button" aria-expanded={open} onclick={() => (open = !open)}>{open ? 'Hide' : 'Details'}</button>
    <button class="btn danger" type="button" onclick={() => onRemove(machine)} aria-label="Remove {machine.name}">Remove</button>
  </div>

  {#if open}
    <div class="detail">
      {#if machine.workloads.length === 0}
        <p class="muted">No workloads reported by this machine.</p>
      {:else}
        <ul>
          {#each machine.workloads as workload (workload.id)}
            <li>
              <strong>{workload.name}</strong>
              <span class="tag">{workload.kind}</span>
              <StatePill state={WORKLOAD_TONE[workload.state] ?? 'busy'} label={workload.state} />
              <span class="muted nums">{workload.cpu} cpu · {formatMb(workload.ram_mb)} · {formatGb(workload.disk_gb)} · {gpuLabel(workload.gpu_mode)}</span>
              {#if workload.address}<span class="mono muted">{workload.address}</span>{/if}
            </li>
          {/each}
        </ul>
      {/if}
      {#if machine.capabilities}
        <p class="muted caps">
          Can run: {machine.capabilities.vm ? 'VMs' : ''}{machine.capabilities.vm && machine.capabilities.container ? ', ' : ''}{machine.capabilities.container ? 'containers' : ''}
          · GPU in VM: {machine.capabilities.gpu_in_vm ? 'yes' : 'no'} · GPU in container: {machine.capabilities.gpu_in_container ? 'yes' : 'no'}
        </p>
      {/if}
      {#if machine.gpu.length}
        <p class="muted caps">GPU: {machine.gpu.map((gpu) => `${gpu.vendor} ${gpu.model}`).join(', ')}</p>
      {/if}
    </div>
  {/if}
</article>

<style>
  .row {
    display: grid;
    grid-template-columns: minmax(150px, 1.3fr) minmax(130px, 1fr) 110px minmax(150px, 1.2fr) minmax(150px, 1.2fr) minmax(100px, 0.8fr) 90px 170px;
    gap: 14px;
    align-items: center;
    padding: 14px 18px;
    border-top: 1px solid var(--line);
  }
  .row.offline .name strong { color: var(--muted); }
  .cell { display: grid; gap: 2px; min-width: 0; }
  .name strong { font-size: 16px; overflow-wrap: anywhere; }
  .tag {
    display: inline-block;
    padding: 0 7px;
    border-radius: 6px;
    background: var(--surface-2);
    border: 1px solid var(--line);
    font-size: 12px;
    font-weight: 600;
  }
  .actions { display: flex; gap: 8px; justify-content: flex-end; }
  .detail { grid-column: 1 / -1; border-top: 1px dashed var(--line); padding-top: 12px; display: grid; gap: 8px; }
  ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  li { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; }
  .caps { font-size: 13px; }

  @media (max-width: 900px) {
    .row { grid-template-columns: 1fr 1fr; padding: 16px; gap: 14px 12px; }
    .name { grid-column: 1 / -1; }
    .cell[data-label]::before {
      content: attr(data-label);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: var(--muted);
    }
    .name[data-label]::before { content: none; }
    .actions { grid-column: 1 / -1; justify-content: flex-start; }
  }
</style>
