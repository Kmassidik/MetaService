<script>
  import StatePill from './StatePill.svelte'
  import Meter from './Meter.svelte'
  import { archName, bundleFlag, formatGb, formatMb, osName, relativeTime } from '../lib/format.js'

  let { machine, now, pinned, onRemove, onAct, onDelete, onInstall, onOpenChat } = $props()
  const flag = $derived(bundleFlag(machine.bundle_version, pinned))
  const WORKLOAD_TONE = { running: 'online', stopped: 'offline' }
  let open = $state(false)
  const gpuLabel = (mode) => ({ none: 'no GPU', container: 'GPU in container', passthrough: 'GPU passthrough' })[mode] ?? mode
</script>

<article class="card" class:offline={machine.state === 'offline'}>
  <div class="ch">
    <div class="row1">
      <span class="nm">{machine.name}</span>
      <span class="id">{machine.ip ?? 'address unknown'}</span>
      <StatePill state={machine.state} />
      {#if machine.problems?.length}<span class="tag warn">Needs setup</span>{/if}
    </div>
    <div class="specs">
      <span>{osName(machine.os)} · {archName(machine.arch)}</span>
      <span>{machine.cpu_cores ?? '–'} cores</span>
      <span>{machine.workloads.length} {machine.workloads.length === 1 ? 'workload' : 'workloads'}</span>
      <span class:stale={flag.stale}>{flag.text}</span>
    </div>
  </div>

  <div class="meters">
    <Meter label="Memory" free={machine.free_ram_mb} total={machine.ram_total_mb} format={formatMb} />
    <Meter label="Disk" free={machine.free_disk_gb} total={machine.disk_total_gb} format={formatGb} />
  </div>

  {#if machine.problems?.length}
    <div class="problems" role="alert">
      <strong>No new workloads are placed on {machine.name} until this is fixed.</strong>
      <ul>
        {#each machine.problems as problem (problem.code)}
          <li><span>{problem.message}</span><span class="fix">{problem.fix}</span></li>
        {/each}
      </ul>
    </div>
  {/if}

  <div class="acts">
    <button class="btn line sm" type="button" aria-expanded={open} onclick={() => (open = !open)}>{open ? 'Hide' : 'Details'}</button>
    <span class="id seen">seen {relativeTime(machine.last_seen, now)}</span>
    <button class="btn danger sm del" type="button" onclick={() => onRemove(machine)} aria-label="Remove {machine.name}">Remove</button>
  </div>

  {#if open}
    <div class="detail">
      <div class="chatbar">
        <button class="btn line sm" type="button" onclick={() => onInstall(machine, null)}>{machine.bundle_version ? 'Reinstall chat' : 'Install chat'} on {machine.name}</button>
        {#if machine.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, null)}>Open chat</button>{/if}
      </div>
      {#if machine.workloads.length === 0}
        <p class="muted">No workloads reported by this machine.</p>
      {:else}
        <ul class="hairlist">
          {#each machine.workloads as workload (workload.id)}
            <li>
              <strong>{workload.name}</strong>
              <span class="tag">{workload.kind}</span>
              <StatePill state={WORKLOAD_TONE[workload.state] ?? 'busy'} label={workload.state} />
              <span class="id nums">{workload.cpu} cpu · {formatMb(workload.ram_mb)} · {formatGb(workload.disk_gb)} · {gpuLabel(workload.gpu_mode)}</span>
              {#if workload.address}<span class="id">{workload.address}</span>{/if}
              <span class="id">{bundleFlag(workload.bundle_version, pinned).text}</span>
              <span class="wl-actions">
                {#if workload.state === 'running'}<button class="btn line sm" type="button" onclick={() => onInstall(machine, workload)}>{workload.bundle_version ? 'Reinstall chat' : 'Install chat'}</button>{/if}
                {#if workload.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, workload)}>Open chat</button>{/if}
                {#if workload.state === 'running'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'stop')}>Stop</button>{/if}
                {#if workload.state === 'stopped'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'start')}>Start</button>{/if}
                <button class="btn danger sm" type="button" onclick={() => onDelete(machine, workload)}>Delete</button>
              </span>
            </li>
          {/each}
        </ul>
      {/if}
      {#if machine.capabilities}
        <p class="id">
          Can run: {machine.capabilities.vm ? 'VMs' : ''}{machine.capabilities.vm && machine.capabilities.container ? ', ' : ''}{machine.capabilities.container ? 'containers' : ''}
          · GPU in VM: {machine.capabilities.gpu_in_vm ? 'yes' : 'no'} · GPU in container: {machine.capabilities.gpu_in_container ? 'yes' : 'no'}
        </p>
      {/if}
      {#if machine.gpu.length}
        <p class="id">GPU: {machine.gpu.map((gpu) => `${gpu.vendor} ${gpu.model}`).join(', ')}</p>
      {/if}
    </div>
  {/if}
</article>

<style>
  .card.offline { opacity: 0.7; }
  .meters { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 14px 16px; border-bottom: 1px solid var(--gray); }
  .problems { display: grid; gap: 6px; padding: 12px 16px; background: var(--warnbg); color: var(--warn); border-bottom: 1px solid var(--warn); font-size: 13px; }
  .problems ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  .problems li { display: grid; gap: 2px; }
  .fix { color: var(--black); font-family: var(--mono); font-size: 11px; }
  .acts .seen { margin-left: 4px; }
  .stale { color: var(--warn); font-weight: 700; }
  .detail { border-top: 1px solid var(--gray); padding: 14px 16px; display: grid; gap: 10px; }
  .chatbar { display: flex; gap: 8px; flex-wrap: wrap; }
  .wl-actions { display: inline-flex; gap: 6px; margin-left: auto; flex-wrap: wrap; }
  .hairlist li { padding: 10px 12px; }
</style>
