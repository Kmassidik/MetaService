<script lang="ts">
  // Machines: the computers MetaService runs on. Open one to see everything about it, its deployments (VMs) and its activity.
  // Find machines and Add a machine live in the sidebar, under Machines.
  import MachineList from '../components/MachineList.svelte'
  import MachineMap from '../components/MachineMap.svelte'
  import ScanView from '../components/ScanView.svelte'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machines, remotes, now, pinned, banner, onAdd, onConnect, onRemove, onRename, onChanged, onCheck, view }: { machines: Machine[]; remotes: RemoteMachineInfo[]; now: number; pinned: string | null | undefined; banner: string; onAdd: () => void; onConnect: (host?: string) => void; onRemove: (machine: Machine) => void; onRename: (machine: Machine) => void; onChanged: () => void; onCheck: (machine: Machine) => void; view: 'list' | 'find' } = $props()
  let mode: 'list' | 'map' = $state('list')
</script>

<div class="phead">
  <h1>Machines</h1><span class="crumb">Infrastructure › {machines.length} {machines.length === 1 ? 'machine' : 'machines'}</span>
  <div class="toggle" role="tablist" aria-label="View">
    <button role="tab" class:active={mode === 'list'} aria-selected={mode === 'list'} onclick={() => (mode = 'list')}>List</button>
    <button role="tab" class:active={mode === 'map'} aria-selected={mode === 'map'} onclick={() => (mode = 'map')}>Map</button>
  </div>
</div>
{#if banner}<p class="banner" role="status">{banner}</p>{/if}
{#if view === 'find'}
  <div class="body"><ScanView {machines} {onConnect} /></div>
{:else if mode === 'map'}
  <MachineMap {machines} hub="macminiruvio" />
{:else}
  <MachineList {machines} {remotes} {now} {pinned} {onRemove} {onRename} {onAdd} {onChanged} {onCheck} />
{/if}

<style>
  .toggle { display: inline-flex; background: #141a22; border: 1px solid #232c38; border-radius: 8px; padding: 2px; margin: 0 0 0 auto; }
  .toggle button { background: transparent; border: none; color: #8b98a6; padding: 6px 14px; border-radius: 6px; cursor: pointer; font-size: 13px; }
  .toggle button.active { background: #1e6b34; color: #eaf7ec; }
  .toggle button:hover:not(.active) { color: #dbe2ea; }
</style>
