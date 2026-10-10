<script>
  // One machine's deployments, as the MAAS detail page does for one server: who it is, its VMs, and what has happened on it.
  import StatePill from '../components/StatePill.svelte'
  import Activity from '../components/Activity.svelte'
  import { archName, bundleFlag, formatGb, formatMb, osName, profileLabel, relativeTime } from '../lib/format.js'

  let { machine, commands, now, pinned, canCreate, onCreate, onAct, onDelete, onOpenChat, onInstall } = $props()
  const TABS = [['overview', 'Overview'], ['vms', 'VMs'], ['activity', 'Activity']]
  const TONE = { running: 'online', stopped: 'offline' }
  let tab = $state('overview')
  const activity = $derived(commands.filter((command) => command.machine === machine?.id))
  const flag = $derived(bundleFlag(machine?.bundle_version, pinned))
  const readyForVms = $derived(canCreate && machine?.state !== 'offline' && !machine?.problems?.length)
  const facts = $derived(machine ? [
    ['ID', machine.id], ['Status', null], ['Address', machine.ip ?? 'unknown'], ['Profile', machine.settings ? profileLabel(machine.settings.profile) : 'unknown'],
    ['System', `${osName(machine.os)} · ${machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch)}`],
    ['CPU', `${machine.cpu_cores ?? '–'} cores`], ['Memory', `${formatMb(machine.free_ram_mb)} free of ${formatMb(machine.ram_total_mb)}`], ['Disk', `${formatGb(machine.free_disk_gb)} free of ${formatGb(machine.disk_total_gb)}`],
    ['Ruvio', flag.text.replace(/^no chat$/, 'not installed')],
  ] : [])
</script>

{#if !machine}
  <div class="empty">No machine with that name. <a class="btn" href="#/deployments">← Deployments</a></div>
{:else}
  <div class="phead">
    <div>
      <div class="titleline"><h1 class="name">{machine.name}</h1><StatePill state={machine.state} />{#if machine.problems?.length}<span class="tag warn">Needs setup</span>{/if}</div>
      <div class="crumb"><a href="#/">Overview</a> › <a href="#/deployments">Deployments</a> › {machine.id}</div>
    </div>
    <div class="sp">
      <button class="btn green sm" type="button" disabled={!readyForVms} title={readyForVms ? '' : 'This machine cannot create VMs yet.'} onclick={() => onCreate(machine)}>＋ Create a VM here</button>
    </div>
  </div>

  <div class="tabs" role="tablist">
    {#each TABS as [id, label] (id)}
      <button type="button" role="tab" class:on={tab === id} aria-selected={tab === id} onclick={() => (tab = id)}>{label}{#if id === 'vms'} ({machine.workloads.length}){/if}</button>
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
    {:else if tab === 'vms'}
      {#if machine.workloads.length === 0}
        <div class="empty" role="status">No VMs on this machine yet.</div>
      {:else}
        <div class="tablewrap flush" role="region" aria-label="VMs on {machine.name}, scroll to view columns">
          <table class="restable">
            <thead><tr><th>VM</th><th>State</th><th>Size</th><th>Address</th><th>Ruvio</th><th></th></tr></thead>
            <tbody>
              {#each machine.workloads as workload (workload.id)}
                <tr>
                  <td class="keep"><b>{workload.name}</b><br><span class="id">{workload.kind}</span></td>
                  <td><StatePill state={TONE[workload.state] ?? 'busy'} label={workload.state} /></td>
                  <td class="nums keep">{workload.cpu} cpu · {formatMb(workload.ram_mb)} · {formatGb(workload.disk_gb)}</td>
                  <td class="id">{workload.address ?? '–'}</td>
                  <td class="id">{bundleFlag(workload.bundle_version, pinned).text}</td>
                  <td>
                    <div class="row-act">
                      {#if workload.state === 'running'}<button class="btn line sm" type="button" onclick={() => onInstall(machine, workload)}>{workload.bundle_version ? 'Reinstall chat' : 'Install chat'}</button>{/if}
                      {#if workload.bundle_version}<button class="btn line sm" type="button" onclick={() => onOpenChat(machine, workload)}>Open chat</button>{/if}
                      {#if workload.state === 'running'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'stop')}>Stop</button>{/if}
                      {#if workload.state === 'stopped'}<button class="btn line sm" type="button" onclick={() => onAct(machine, workload, 'start')}>Start</button>{/if}
                      <button class="btn danger sm" type="button" onclick={() => onDelete(machine, workload)}>Delete</button>
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
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
  .flush { padding-left: 0; padding-right: 0; margin-left: 0; }
  .keep { white-space: nowrap; }
  @media (max-width: 820px) { .tabs, .tabbody { padding-left: 16px; padding-right: 16px; } .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
