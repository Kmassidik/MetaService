<script>
  import StatePill from './StatePill.svelte'
  import Meter from './Meter.svelte'
  import { archName, bundleFlag, formatGb, formatMb, osName, relativeTime } from '../lib/format.js'

  let { machine, now, pinned, onRemove, onAct, onDelete, onInstall, onOpenChat } = $props()
  const flag = $derived(bundleFlag(machine.bundle_version, pinned))
  const WORKLOAD_TONE = { running: 'online', stopped: 'offline' }
  let open = $state(false)
  /** This machine is the one the control plane runs on: it reaches the Root over its own loopback address. */
  /** The machine the control panel runs on enrolls over its own loopback address. It is the parent, and machine 1. */
  const isParent = $derived(machine.ip === '127.0.0.1')
  const chip = $derived(machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch))
  const vmCount = $derived(machine.workloads.length)
  const gpuLabel = (mode) => ({ none: 'no GPU', container: 'GPU in container', passthrough: 'GPU passthrough' })[mode] ?? mode
</script>

<article class="card" class:offline={machine.state === 'offline'}>
  <div class="ch">
    <div class="row1">
      <span class="nm">{machine.name}</span>
      {#if isParent}<span class="tag run">Parent</span>{/if}
      <StatePill state={machine.state} />
      {#if machine.problems?.length}<span class="tag warn">Needs setup</span>{/if}
    </div>
    <div class="where">{machine.ip ?? 'address unknown'}</div>
    <div class="specs">
      <span>{osName(machine.os)} · {chip}</span>
      <span>{machine.cpu_cores ?? '–'} cores</span>
      <span>{vmCount === 0 ? 'No VMs yet' : vmCount === 1 ? '1 VM' : `${vmCount} VMs`}</span>
      {#if machine.bundle_version}<span class:stale={flag.stale}>{flag.text}</span>{/if}
    </div>
  </div>

  <div class="meters">
    <Meter label="Memory" free={machine.free_ram_mb} total={machine.ram_total_mb} format={formatMb} />
    <Meter label="Disk" free={machine.free_disk_gb} total={machine.disk_total_gb} format={formatGb} />
  </div>

  {#if machine.problems?.length}
    <div class="problems" role="alert">
      <strong>VMs can't be created on this machine yet.</strong>
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
        <span class="id" class:stale={flag.stale}>Chat on this machine: {flag.text.replace(/^no chat$/, 'not installed')}</span>
        <button class="btn line sm" type="button" onclick={() => onInstall(machine, null)}>{machine.bundle_version ? 'Reinstall chat' : 'Install chat'}</button>
        {#if machine.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, null)}>Open chat</button>{/if}
      </div>
      {#if machine.workloads.length === 0}
        <p class="muted">No VMs on this machine yet.</p>
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
          Can run: {machine.capabilities.vm || machine.capabilities.container ? [machine.capabilities.vm && 'VMs', machine.capabilities.container && 'containers'].filter(Boolean).join(' and ') : 'nothing yet'}
          · GPU in a VM: {machine.capabilities.gpu_in_vm ? 'yes' : 'no'} · GPU in a container: {machine.capabilities.gpu_in_container ? 'yes' : 'no'}
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
  .where { font-family: var(--mono); font-size: 11px; color: var(--m50); margin-top: 3px; }
  .nm { overflow-wrap: anywhere; }
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
