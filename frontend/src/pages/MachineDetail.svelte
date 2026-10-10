<script>
  // One machine, as the MAAS detail page is for one server: who it is, its deployments (the VMs on it) and what has happened on it.
  import StatePill from '../components/StatePill.svelte'
  import Activity from '../components/Activity.svelte'
  import DeploymentsView from '../components/deployments/DeploymentsView.svelte'
  import { archName, bundleFlag, formatGb, formatMb, osName, profileLabel, relativeTime } from '../lib/format.js'

  let { machine, commands, now, pinned, onCreate, onRemove, onAct, onDelete, onOpenChat, onInstall } = $props()
  const TABS = [['overview', 'Overview'], ['deployments', 'Deployments'], ['activity', 'Activity']]
  let tab = $state('overview')
  const activity = $derived(commands.filter((command) => command.machine === machine?.id))
  const flag = $derived(bundleFlag(machine?.bundle_version, pinned))
  const readyForVms = $derived(machine?.state !== 'offline' && !machine?.problems?.length)
  const settings = $derived(machine?.settings)
  const reserved = $derived(settings && (settings.ram_reserve_mb != null || settings.disk_reserve_gb != null))
  const gpuLabel = (mode) => ({ none: 'no GPU', container: 'GPU in container', passthrough: 'GPU passthrough' })[mode] ?? mode
  const facts = $derived(machine ? [
    ['ID', machine.id], ['Status', null], ['Address', machine.ip ?? 'unknown'], ['Profile', machine.settings ? profileLabel(machine.settings.profile) : 'unknown'],
    ['System', `${osName(machine.os)} · ${machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch)}`],
    ['CPU', `${machine.cpu_cores ?? '–'} cores`], ['Memory', `${formatMb(machine.free_ram_mb)} free of ${formatMb(machine.ram_total_mb)}`], ['Disk', `${formatGb(machine.free_disk_gb)} free of ${formatGb(machine.disk_total_gb)}`],
    ['Ruvio', flag.text.replace(/^no chat$/, 'not installed')],
  ] : [])
</script>

{#if !machine}
  <div class="empty">No machine with that name. <a class="btn" href="#/machines">← Machines</a></div>
{:else}
  <div class="phead">
    <div>
      <div class="titleline"><h1 class="name">{machine.name}</h1><StatePill state={machine.state} />{#if machine.problems?.length}<span class="tag warn">Needs setup</span>{/if}</div>
      <div class="crumb"><a href="#/">Overview</a> › <a href="#/machines">Machines</a> › {machine.id}</div>
    </div>
    <div class="sp">
      <button class="btn green sm" type="button" disabled={!readyForVms} title={readyForVms ? '' : 'This machine cannot create VMs yet.'} onclick={() => onCreate(machine)}>＋ Create a VM here</button>
      <button class="btn danger sm" type="button" onclick={() => onRemove(machine)} aria-label="Remove {machine.name}">Remove</button>
    </div>
  </div>

  <div class="tabs" role="tablist">
    {#each TABS as [id, label] (id)}
      <button type="button" role="tab" class:on={tab === id} aria-selected={tab === id} onclick={() => (tab = id)}>{label}{#if id === 'deployments'}{' '}({machine.workloads.length}){/if}</button>
    {/each}
  </div>

  <div class="tabbody">
    {#if tab === 'overview'}
      {#if machine.problems?.length}
        <div class="op-alerts flush" role="alert">
          {#each machine.problems as problem (problem.code)}<div class="op-alert"><b>{problem.message}</b><p>{problem.fix}</p></div>{/each}
        </div>
      {/if}
      <dl class="kv">
        {#each facts as [label, value] (label)}
          <div><dt>{label}</dt><dd>{#if value === null}<StatePill state={machine.state} />{:else}{value}{/if}</dd></div>
        {/each}
        <div><dt>Last seen</dt><dd>{relativeTime(machine.last_seen, now)}</dd></div>
      </dl>
      <div class="chatbar">
        <button class="btn line sm" type="button" onclick={() => onInstall(machine, null)}>{machine.bundle_version ? 'Reinstall chat' : 'Install chat'}</button>
        {#if machine.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, null)}>Open chat</button>{/if}
      </div>
      {#if machine.capabilities}
        <p class="id">
          Can run: {machine.capabilities.vm || machine.capabilities.container ? [machine.capabilities.vm && 'VMs', machine.capabilities.container && 'containers'].filter(Boolean).join(' and ') : 'nothing yet'}
          · GPU in a VM: {machine.capabilities.gpu_in_vm ? 'yes' : 'no'} · GPU in a container: {machine.capabilities.gpu_in_container ? 'yes' : 'no'}
        </p>
      {/if}
      {#if machine.gpu.length}<p class="id">GPU: {machine.gpu.map((gpu) => `${gpu.vendor} ${gpu.model}`).join(', ')}</p>{/if}
      {#if settings}
        <h2 class="subhead">How this machine was set up</h2>
        <dl class="kv">
          {#if settings.labels?.length}<div><dt>Labels</dt><dd>{#each settings.labels as label (label)}<span class="tag">{label}</span>{/each}</dd></div>{/if}
          {#if settings.notes}<div><dt>Notes</dt><dd>{settings.notes}</dd></div>{/if}
          {#if reserved}<div><dt>Kept free</dt><dd>{settings.ram_reserve_mb ?? 0} MB memory · {settings.disk_reserve_gb ?? 0} GB disk</dd></div>{/if}
          {#if settings.ram_allowance_mb || settings.disk_allowance_gb}<div><dt>Most VMs may use</dt><dd>{settings.ram_allowance_mb ? `${settings.ram_allowance_mb} MB memory` : 'any memory'} · {settings.disk_allowance_gb ? `${settings.disk_allowance_gb} GB disk` : 'any disk'}</dd></div>{/if}
          <div><dt>GPU for VMs</dt><dd>{settings.allow_gpu ? 'offered' : 'not offered'}</dd></div>
          {#if settings.vm_cpu || settings.vm_ram_mb || settings.vm_disk_gb}<div><dt>A new VM gets</dt><dd>{settings.vm_cpu ?? '–'} CPU · {settings.vm_ram_mb ?? '–'} MB · {settings.vm_disk_gb ?? '–'} GB{settings.vm_image ? ` · ${settings.vm_image}` : ''}</dd></div>{/if}
          {#if settings.vm_max_running}<div><dt>Most VMs at once</dt><dd>{settings.vm_max_running}</dd></div>{/if}
          {#if settings.subdomain}<div><dt>Name on the internet</dt><dd>{settings.subdomain}{settings.public_chat ? ' · chat public' : ''} (takes effect when the domain is connected)</dd></div>{/if}
          {#if settings.ai_model}<div><dt>Chat model</dt><dd>{settings.ai_model}</dd></div>{/if}
        </dl>
      {/if}
    {:else if tab === 'deployments'}
      <DeploymentsView {machine} {pinned} onCreate={() => onCreate(machine)} {onAct} {onDelete} {onOpenChat} {onInstall} />
    {:else}
      <Activity commands={activity} {now} />
    {/if}
  </div>
{/if}

<style>
  .titleline { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .name { letter-spacing: 0; text-transform: none; font-size: 18px; }
  .crumb { margin-top: 4px; }
  .tabs { display: flex; border-bottom: 1px solid var(--gray); padding: 0 28px; }
  .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; padding: 12px 16px; font-family: var(--mono); font-size: 12px; color: var(--m50); margin-bottom: -1px; }
  .tabs button.on { color: var(--black); border-bottom-color: var(--green); font-weight: 700; }
  .tabbody { padding: 24px 28px; }
  .kv { display: grid; gap: 14px; margin: 0; max-width: 820px; }
  .kv > div { display: grid; grid-template-columns: 120px 1fr; align-items: center; gap: 16px; border-bottom: 1px solid var(--gray2); padding-bottom: 12px; }
  .kv dt { font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .chatbar { display: flex; gap: 8px; margin-top: 20px; }
  .subhead { margin: 28px 0 14px; font: 700 13px var(--mono); letter-spacing: 0.1em; text-transform: uppercase; }
  .flush { padding-left: 0; padding-right: 0; margin-left: 0; }
  @media (max-width: 820px) { .tabs, .tabbody { padding-left: 16px; padding-right: 16px; } .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
