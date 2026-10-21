<script lang="ts">
  // One VM, as the MAAS detail page shows one server: same header, tabs (Overview, Monitoring, Access, Danger), rows and wording, fed by MetaService data.
  import VmOverview from '../components/vm/VmOverview.svelte'
  import VmMonitoring from '../components/vm/VmMonitoring.svelte'
  import VmAccess from '../components/vm/VmAccess.svelte'
  import VmDanger from '../components/vm/VmDanger.svelte'
  import GpuBadge from '../components/GpuBadge.svelte'
  import VmGpu from '../components/vm/VmGpu.svelte'
  import { hasGpu } from '../lib/gpuChoice.ts'
  import { machineHref } from '../lib/routes.ts'
  import { consoleTitle, terminalAccess } from '../lib/terminalAccess.ts'
  import { openConsole } from '../lib/terminalStore.svelte.ts'
  import { findServer, findWorkload, headerAction, tabLabel, VM_TABS } from '../lib/vm.ts'
  import type { VmTab } from '../lib/vm.ts'
  import type { Machine, Workload } from '../lib/types.ts'

  interface Props {
    machine: Machine | undefined
    workloadId: string
    pinned: string | null | undefined
    banner: string
    onAct: (machine: Machine, workload: Workload, action: 'start' | 'stop') => void
    onDelete: (machine: Machine, workload: Workload) => void
    onOpenChat: (machine: Machine, workload: Workload | null) => void
    onInstall: (machine: Machine, workload: Workload | null) => void
  }

  let { machine, workloadId, pinned, banner, onAct, onDelete, onOpenChat, onInstall }: Props = $props()
  let tab: VmTab = $state('overview')
  const workload = $derived(machine ? findWorkload(machine, workloadId) : undefined)
  const server = $derived(machine ? findServer(machine, workloadId) : undefined)
  const access = $derived(machine && workload ? terminalAccess(machine, workload) : null)
  const action = $derived(workload ? headerAction(workload.state) : null)

  function copy(text: string) {
    void navigator.clipboard?.writeText(text)
  }
</script>

{#if banner}<div class="empty" role="alert">{banner}</div>{/if}
{#if !machine}
  <div class="empty">No machine with that name. <a class="btn" href="#/machines">← Machines</a></div>
{:else if !workload || !server}
  <div class="empty">VM not found.<a class="btn" href={machineHref(machine.id)}>← {machine.name}</a></div>
{:else}
  <div class="phead">
    <div>
      <div class="titleline"><h1 class="name">{server.display}</h1><span class="tag {server.cls}">{server.status}</span>{#if hasGpu(workload)}<GpuBadge />{/if}</div>
      <div class="crumb"><a href="#/">Overview</a> › <a href="#/machines">Machines</a> › <a href={machineHref(machine.id)}>{machine.name}</a> › {workload.id}</div>
    </div>
    <div class="sp">
      {#if access?.allowed}<button class="btn line" type="button" onclick={() => openConsole({ machine: machine.id, workload: workload.id, name: consoleTitle(workload) })}>▸ Web terminal</button>{/if}
      {#if workload.bundle_version}<button class="btn line" type="button" onclick={() => onOpenChat(machine, workload)}>Open chat</button>{/if}
      {#if action}<button class="btn line" type="button" onclick={() => onAct(machine, workload, action)}>{action === 'start' ? 'Start' : 'Stop'}</button>{/if}
    </div>
  </div>

  <div class="tabs" role="tablist">
    {#each VM_TABS as id (id)}
      <button type="button" role="tab" class:on={tab === id} aria-selected={tab === id} onclick={() => (tab = id)}>{tabLabel(id)}</button>
    {/each}
  </div>

  <div class="tabbody">
    {#if tab === 'overview'}
      <VmOverview {machine} {workload} {server} {pinned} onInstall={() => onInstall(machine, workload)} />
      {#if hasGpu(workload)}{#key workload.id}<VmGpu machineId={machine.id} workloadId={workload.id} />{/key}{/if}
    {:else if tab === 'monitoring'}
      <VmMonitoring state={workload.state} />
    {:else if tab === 'access'}
      <VmAccess {workload} onCopy={copy} onOpenChat={() => onOpenChat(machine, workload)} />
    {:else}
      <VmDanger onDelete={() => onDelete(machine, workload)} />
    {/if}
  </div>
{/if}

<style>
  .titleline { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .name { letter-spacing: 0; text-transform: none; font-size: 18px; }
  .crumb { margin-top: 4px; }
  .tabs { display: flex; border-bottom: 1px solid var(--line); padding: 0 28px; }
  .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; padding: 12px 16px; font-family: var(--mono); font-size: 12px; color: var(--m50); margin-bottom: -1px; }
  .tabs button.on { color: var(--text); border-bottom-color: var(--accent-mark); font-weight: 700; }
  .tabbody { padding: 24px 28px; max-width: 820px; }
  @media (max-width: 820px) { .tabs, .tabbody { padding-left: 16px; padding-right: 16px; } }
</style>
