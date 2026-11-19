<script lang="ts">
  // Machines: the computers MetaService runs on. Open one to see everything about it, its deployments (VMs) and its activity.
  // Find machines and Add a machine live in the sidebar, under Machines.
  // Two view modes (List, Map) as toggle tabs; the search box filters whichever view is active via route query (?q=).
  import MachineList from '../components/MachineList.svelte'
  import { queryMachines } from '../lib/machineQuery.ts'
  import MachineMap from '../components/MachineMap.svelte'
  import ScanView from '../components/ScanView.svelte'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machines, remotes, now, pinned, banner, onAdd, onConnect, onRemove, onRename, onChanged, onCheck, view }: { machines: Machine[]; remotes: RemoteMachineInfo[]; now: number; pinned: string | null | undefined; banner: string; onAdd: () => void; onConnect: (host?: string) => void; onRemove: (machine: Machine) => void; onRename: (machine: Machine) => void; onChanged: () => void; onCheck: (machine: Machine) => void; view: 'list' | 'find' } = $props()

  const QUERY_PARAM = 'q'
  const TAB_PARAM = 'tab'
  const TABS = ['list', 'map'] as const
  type Mode = (typeof TABS)[number]

  let params = $state(new URLSearchParams(location.hash.split('?')[1] ?? ''))
  let query = $derived(params.get(QUERY_PARAM) ?? '')
  let mode: Mode = $derived(TABS.includes(params.get(TAB_PARAM) as Mode) ? (params.get(TAB_PARAM) as Mode) : 'list')

  function navigate(patch: Record<string, string | null>): void {
    const next = new URLSearchParams(params)
    for (const [key, value] of Object.entries(patch)) {
      if (value === null || value === '') next.delete(key)
      else next.set(key, value)
    }
    const base = location.hash.split('?')[0] ?? '#/machines'
    const qs = next.toString()
    location.hash = qs ? `${base}?${qs}` : base
  }

  $effect(() => {
    const onHashChange = () => {
      params = new URLSearchParams(location.hash.split('?')[1] ?? '')
    }
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  })

  function setQuery(value: string): void {
    navigate({ [QUERY_PARAM]: value || null })
  }

  function setMode(next: Mode): void {
    navigate({ [TAB_PARAM]: next === 'list' ? null : next })
  }

  const filtered = $derived(query.trim() ? queryMachines(machines, query) : machines)
</script>

<div class="phead">
  <h1>Machines</h1><span class="crumb">Infrastructure › {filtered.length} {filtered.length === 1 ? 'machine' : 'machines'}</span>
  <div class="viewtoggle" role="tablist" aria-label="View">
    <button class="btn line sm" class:active={mode === 'list'} role="tab" aria-selected={mode === 'list'} onclick={() => setMode('list')}>List</button>
    <button class="btn line sm" class:active={mode === 'map'} role="tab" aria-selected={mode === 'map'} onclick={() => setMode('map')}>Map</button>
  </div>
</div>
{#if banner}<p class="banner" role="status">{banner}</p>{/if}
{#if view === 'find'}
  <div class="body"><ScanView {machines} {onConnect} /></div>
{:else if mode === 'map'}
  <div class="mapwrap"><MachineMap machines={filtered} hub="macminiruvio" /></div>
{:else}
  <div class="body searchrow">
    <input class="querybox" type="search" placeholder="Search: name, os, ip… or os:linux state:offline ip:10.77" value={query} oninput={(e) => setQuery((e.target as HTMLInputElement).value)} aria-label="Search machines" />
    {#if query.trim()}
      <button type="button" class="btn line sm clear" onclick={() => setQuery('')} aria-label="Clear search">✕ clear</button>
    {/if}
  </div>
  <div class="body">
    {#if query.trim()}
      <p class="querycount">{filtered.length} of {machines.length} machines match</p>
    {/if}
    <MachineList machines={filtered} {remotes} {now} {pinned} {onRemove} {onRename} {onAdd} {onChanged} {onCheck} />
  </div>
{/if}

<style>
  .mapwrap { position: relative; }
  .searchrow { display: flex; gap: 8px; align-items: center; }
  .querybox { width: 100%; max-width: 560px; padding: 10px 14px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); color: var(--text); font-size: 14px; }
  .querycount { color: var(--muted); font-size: 12px; margin: 8px 0 0; }
  .viewtoggle { display: inline-flex; gap: 8px; margin: 0 0 0 auto; }
  .viewtoggle .btn.active { background: var(--accent); border-color: var(--accent); color: var(--accent-text); }
</style>
