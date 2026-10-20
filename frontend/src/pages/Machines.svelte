<script lang="ts">
  // Machines: the computers MetaService runs on. Open one to see everything about it, its deployments (VMs) and its activity.
  // Find machines, Connect a computer (the list of connected computers) and Add a machine live in the sidebar, under Machines.
  import MachineList from '../components/MachineList.svelte'
  import ScanView from '../components/ScanView.svelte'
  import ConnectedComputers from '../components/ConnectedComputers.svelte'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machines, remoteInfos, now, pinned, banner, onAdd, onConnect, onRemove, view }: { machines: Machine[]; remoteInfos: RemoteMachineInfo[]; now: number; pinned: string | null | undefined; banner: string; onAdd: () => void; onConnect: (host?: string) => void; onRemove: (machine: Machine) => void; view: 'list' | 'find' | 'connect' } = $props()
</script>

<div class="phead">
  <h1>Machines</h1><span class="crumb">Infrastructure › {machines.length} {machines.length === 1 ? 'machine' : 'machines'}</span>
</div>
{#if banner}<p class="banner" role="status">{banner}</p>{/if}
{#if view === 'find'}
  <div class="body"><ScanView {onConnect} /></div>
{:else if view === 'connect'}
  <div class="body"><ConnectedComputers infos={remoteInfos} {machines} {now} onConnect={() => onConnect()} {onRemove} /></div>
{:else}
  <MachineList {machines} {now} {pinned} {onRemove} {onAdd} />
{/if}
