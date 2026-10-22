<script lang="ts">
  // One machine, not one VM: how it is doing right now (Live), the VMs on it, what it is and how it is set (Environment), and what has happened on it (Activity).
  import Owl from '../components/Owl.svelte'
  import StatePill from '../components/StatePill.svelte'
  import Activity from '../components/Activity.svelte'
  import DeploymentsView from '../components/deployments/DeploymentsView.svelte'
  import EnvironmentTab from '../components/environment/EnvironmentTab.svelte'
  import Monitor from '../components/monitor/Monitor.svelte'
  import PendingVms from '../components/vms/PendingVms.svelte'
  import { machineTabs, nextTab, pollsLive, type MachineTab } from '../lib/machineTabs.ts'
  import { pendingFor, type PendingVm } from '../lib/pendingVms.ts'
  import { machineTabFromRoute } from '../lib/routes.ts'
  import type { Command, Machine, RemoteMachineInfo, Workload } from '../lib/types.ts'

  interface Props {
    machine: Machine | undefined
    remote: RemoteMachineInfo | null
    commands: Command[]
    /** VMs being made, on any machine; this page shows the ones for its own machine. */
    pending: PendingVm[]
    /** The address of the page, which may name a tab (&tab=). */
    route: string
    now: number
    pinned: string | null | undefined
    /** The highest helper version any machine reports, to mark an old one. */
    newestHelper: string | null
    /** How many chat versions the parent has built. */
    chatsBuilt: number
    onCreate: (machine: Machine) => void
    onRemove: (machine: Machine) => void
    onAct: (machine: Machine, workload: Workload, action: 'start' | 'stop') => Promise<void>
    onDelete: (machine: Machine, workload: Workload) => void
    onOpenChat: (machine: Machine, workload: Workload | null) => void
    onInstall: (machine: Machine, workload: Workload | null) => Promise<unknown>
    /** Ruvio on or off for the machine. Answers the parent's refusal text, or null when it went through. */
    onRuvio: (machine: Machine, on: boolean) => Promise<unknown>
    /** Something changed on the parent (settings saved, Ruvio switched): read the machines again. */
    onChanged: () => void
  }

  let { machine, remote, commands, pending, route, now, pinned, newestHelper, chatsBuilt, onCreate, onRemove, onAct, onDelete, onOpenChat, onInstall, onRuvio, onChanged }: Props = $props()
  /** The tab the person picked; empty until they pick one, so the address decides which tab opens. */
  let picked: MachineTab | null = $state(null)
  const tab = $derived(picked ?? machineTabFromRoute(route))
  const activity = $derived(commands.filter((command: Command) => command.machine === machine?.id))
  const making = $derived(machine ? pendingFor(pending, machine.id) : [])
  const tabs = $derived(machineTabs(machine ? machine.workloads.length + making.length : 0))
  const readyForVms = $derived(machine?.state !== 'offline' && !machine?.problems?.length)

  // A new address (another machine, or a link that names a tab) starts from what the address says.
  $effect(() => {
    void route
    picked = null
  })

  const tabId = (id: MachineTab) => `machine-tab-${id}`
  const panelId = (id: MachineTab) => `machine-panel-${id}`

  function onTabKey(event: KeyboardEvent, from: MachineTab) {
    const target = nextTab(from, event.key)
    if (target === null) return
    event.preventDefault()
    picked = target
    document.getElementById(tabId(target))?.focus()
  }
</script>

{#if !machine}
  <div class="empty stage"><Owl name="notFound" />No machine with that name. <a class="btn" href="#/machines">← Machines</a></div>
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

  <PendingVms pending={making} showMachine={false} compact />

  <div class="tabs" role="tablist" aria-label="This machine">
    {#each tabs as { id, label } (id)}
      <button type="button" role="tab" id={tabId(id)} class:on={tab === id} aria-selected={tab === id} aria-controls={panelId(id)} tabindex={tab === id ? 0 : -1} onclick={() => (picked = id)} onkeydown={(event) => onTabKey(event, id)}>{label}</button>
    {/each}
  </div>

  <div class="tabbody" role="tabpanel" id={panelId('live')} aria-labelledby={tabId('live')} hidden={tab !== 'live'}>
    {#key machine.id}<Monitor {machine} {now} active={pollsLive(tab)} />{/key}
  </div>
  <div class="tabbody" role="tabpanel" id={panelId('vms')} aria-labelledby={tabId('vms')} hidden={tab !== 'vms'}>
    {#if tab === 'vms'}
      <DeploymentsView {machine} {pinned} making={making.length} onCreate={() => onCreate(machine)} {onAct} {onDelete} {onOpenChat} {onInstall} />
    {/if}
  </div>
  <div class="tabbody" role="tabpanel" id={panelId('environment')} aria-labelledby={tabId('environment')} hidden={tab !== 'environment'}>
    {#if tab === 'environment'}
      {#key machine.id}
        <EnvironmentTab {machine} {remote} {now} {newestHelper} {chatsBuilt} {onRuvio} {onOpenChat} {onChanged} />
      {/key}
    {/if}
  </div>
  <div class="tabbody" role="tabpanel" id={panelId('activity')} aria-labelledby={tabId('activity')} hidden={tab !== 'activity'}>
    {#if tab === 'activity'}<Activity commands={activity} {now} />{/if}
  </div>
{/if}

<style>
  .titleline { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .name { letter-spacing: 0; text-transform: none; font-size: 18px; }
  .crumb { margin-top: 4px; }
  .tabs { display: flex; overflow-x: auto; border-bottom: 1px solid var(--line); padding: 0 28px; }
  .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; padding: 12px 16px; font-family: var(--mono); font-size: 12px; color: var(--m50); margin-bottom: -1px; white-space: nowrap; }
  .tabs button.on { color: var(--text); border-bottom-color: var(--accent-mark); font-weight: 700; }
  .tabbody { padding: 24px 28px; }
  @media (max-width: 820px) { .tabs, .tabbody { padding-left: 16px; padding-right: 16px; } }
</style>
