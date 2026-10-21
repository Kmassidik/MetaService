<script lang="ts">
  // One machine, not one VM: what it is and can run (Overview), what is installed on it and how it is set (Environment), the VMs on it (Deployments) and what has happened on it.
  import StatePill from '../components/StatePill.svelte'
  import Activity from '../components/Activity.svelte'
  import DeploymentsView from '../components/deployments/DeploymentsView.svelte'
  import EnvironmentTab from '../components/environment/EnvironmentTab.svelte'
  import Monitor from '../components/monitor/Monitor.svelte'
  import { canRunText, gpuText } from '../lib/environment.ts'
  import { archName, formatGb, formatMb, osName, relativeTime } from '../lib/format.ts'
  import type { Command, Machine, RemoteMachineInfo, Workload } from '../lib/types.ts'

  type Tab = 'overview' | 'environment' | 'deployments' | 'activity'

  interface Props {
    machine: Machine | undefined
    remote: RemoteMachineInfo | null
    commands: Command[]
    now: number
    pinned: string | null | undefined
    /** The highest helper version any machine reports, to mark an old one. */
    newestHelper: string | null
    /** How many chat versions the parent has built. */
    chatsBuilt: number
    onCreate: (machine: Machine) => void
    onRemove: (machine: Machine) => void
    onAct: (machine: Machine, workload: Workload, action: 'start' | 'stop') => void
    onDelete: (machine: Machine, workload: Workload) => void
    onOpenChat: (machine: Machine, workload: Workload | null) => void
    onInstall: (machine: Machine, workload: Workload | null) => void
    /** Ruvio on or off for the machine. Answers the parent's refusal text, or null when it went through. */
    onRuvio: (machine: Machine, on: boolean) => Promise<string | null>
    /** Something changed on the parent (settings saved, Ruvio switched): read the machines again. */
    onChanged: () => void
  }

  let { machine, remote, commands, now, pinned, newestHelper, chatsBuilt, onCreate, onRemove, onAct, onDelete, onOpenChat, onInstall, onRuvio, onChanged }: Props = $props()
  const TABS: [Tab, string][] = [['overview', 'Overview'], ['environment', 'Environment'], ['deployments', 'Deployments'], ['activity', 'Activity']]
  let tab: Tab = $state('overview')
  const activity = $derived(commands.filter((command: Command) => command.machine === machine?.id))
  const readyForVms = $derived(machine?.state !== 'offline' && !machine?.problems?.length)
  const facts = $derived(machine ? [
    ['ID', machine.id], ['Status', null], ['Address', machine.ip ?? 'unknown'],
    ['System', `${osName(machine.os)} · ${machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch)}`],
    ['CPU', `${machine.cpu_cores ?? '–'} cores`], ['Memory', `${formatMb(machine.free_ram_mb)} free of ${formatMb(machine.ram_total_mb)}`], ['Disk', `${formatGb(machine.free_disk_gb)} free of ${formatGb(machine.disk_total_gb)}`],
    ['GPU', gpuText(machine.gpu)],
    ['Last seen', relativeTime(machine.last_seen, now)],
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

  {#key machine.id}<Monitor {machine} {now} />{/key}

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
      </dl>
      <p class="id">{canRunText(machine.capabilities)}</p>
    {:else if tab === 'environment'}
      {#key machine.id}
        <EnvironmentTab {machine} {remote} {now} {newestHelper} {chatsBuilt} {onRuvio} {onOpenChat} {onChanged} />
      {/key}
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
  .tabs { display: flex; overflow-x: auto; border-bottom: 1px solid var(--gray); padding: 0 28px; }
  .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; padding: 12px 16px; font-family: var(--mono); font-size: 12px; color: var(--m50); margin-bottom: -1px; }
  .tabs button.on { color: var(--black); border-bottom-color: var(--green); font-weight: 700; }
  .tabbody { padding: 24px 28px; }
  .id { margin: 18px 0 0; }
  .kv { display: grid; gap: 14px; margin: 0; max-width: 820px; }
  .kv > div { display: grid; grid-template-columns: 120px 1fr; align-items: center; gap: 16px; border-bottom: 1px solid var(--gray2); padding-bottom: 12px; }
  .kv dt { font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .flush { padding-left: 0; padding-right: 0; margin-left: 0; }
  @media (max-width: 820px) { .tabs, .tabbody { padding-left: 16px; padding-right: 16px; } .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
