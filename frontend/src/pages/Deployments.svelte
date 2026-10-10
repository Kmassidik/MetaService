<script>
  // Deployments, as in the MAAS panel: one line per place that runs VMs. Open a machine to see its VMs and what has happened on it.
  import StatePill from '../components/StatePill.svelte'
  import { bundleFlag } from '../lib/format.js'

  let { machines, pinned, canCreate, cannotCreateReason, onCreate } = $props()
  const vmWord = (count) => (count === 1 ? '1 VM' : `${count} VMs`)
  const running = (machine) => machine.workloads.filter((workload) => workload.state === 'running').length
</script>

<div class="phead">
  <h1>Deployments</h1><span class="crumb">Infrastructure › {machines.length} {machines.length === 1 ? 'machine' : 'machines'}</span>
  <div class="sp">
    <button class="btn green sm" type="button" disabled={!canCreate} title={canCreate ? '' : cannotCreateReason} onclick={() => onCreate(null)}>＋ Create a VM</button>
    {#if !canCreate}<span class="id" role="status">{cannotCreateReason}</span>{/if}
  </div>
</div>
{#if machines.length === 0}
  <div class="empty" role="status">No machines yet, so nothing is deployed. Add a machine first.<a class="btn green sm" href="#/machines">Go to Machines</a></div>
{:else}
  <div class="tablewrap" role="region" aria-label="Deployments per machine, scroll to view columns">
    <table class="restable">
      <thead><tr><th>Machine</th><th>State</th><th>VMs</th><th>Address</th><th>Ruvio</th><th></th></tr></thead>
      <tbody>
        {#each machines as machine (machine.id)}
          <tr>
            <td class="keep"><a href={'#/deployments/' + machine.id}><b>{machine.name}</b></a></td>
            <td><StatePill state={machine.state} /></td>
            <td class="keep">{vmWord(machine.workloads.length)}{#if machine.workloads.length > 0} <span class="id">· {running(machine)} running</span>{/if}</td>
            <td class="id">{machine.ip ?? '–'}</td>
            <td class="id">{bundleFlag(machine.bundle_version, pinned).text}</td>
            <td><div class="row-act"><a class="btn line sm" href={'#/deployments/' + machine.id}>Open</a></div></td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<style>
  .keep { white-space: nowrap; }
</style>
