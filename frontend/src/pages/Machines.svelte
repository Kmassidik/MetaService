<script>
  // Machines: the computers MetaService runs on. Open one to see everything about it, its deployments (VMs) and its activity.
  import MachineList from '../components/MachineList.svelte'
  import ScanView from '../components/ScanView.svelte'

  let { machines, now, pinned, banner, onAdd, onRemove, showScan } = $props()
</script>

<div class="phead">
  <h1>Machines</h1><span class="crumb">Infrastructure › {machines.length} {machines.length === 1 ? 'machine' : 'machines'}</span>
  <div class="sp">
    <a class="btn line sm" href={showScan ? '#/machines' : '#/machines/find'}>{showScan ? 'Back to machines' : 'Find machines'}</a>
    <button class="btn green sm" type="button" onclick={onAdd}>＋ Add a machine</button>
  </div>
</div>
{#if banner}<p class="banner" role="status">{banner}</p>{/if}
{#if showScan}
  <div class="body"><ScanView /></div>
{:else}
  <MachineList {machines} {now} {pinned} {onRemove} {onAdd} />
{/if}
