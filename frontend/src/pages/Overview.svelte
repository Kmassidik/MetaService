<script lang="ts">
  // Overview, as in the MAAS panel: the summary cards, the services behind the panel, and what needs the operator.
  import Owl from '../components/Owl.svelte'
  import { attentionItems, overviewCounts } from '../lib/overview.ts'

  import type { Machine } from '../lib/types.ts'

  let { machines }: { machines: Machine[] } = $props()
  const counts = $derived(overviewCounts(machines))
  const items = $derived(attentionItems(machines))
  const cards = $derived([['Machines', counts.machines], ['Online', counts.online], ['VMs', counts.vms], ['Running', counts.running], ['Need attention', counts.needAttention]])
</script>

<div class="phead"><h1>Overview</h1><span class="crumb">Operator › Overview</span></div>
<section class="op-stats" aria-label="Summary">
  {#each cards as [label, count] (label)}<div class="op-stat"><span>{label}</span><b class="nums">{count}</b></div>{/each}
</section>
<h2 class="op-subhead">Services</h2>
<section class="op-health" aria-label="Services">
  <div class="op-service"><span class="tag run">healthy</span><b>Control panel</b><span class="muted">Answering you now.</span></div>
</section>
<h2 class="op-subhead">Needs attention</h2>
{#if items.length === 0 && machines.length === 0}
  <div class="empty stage" role="status"><Owl name="emptyMachines" />No machines yet. Add the first one from Machines.</div>
{:else if items.length === 0}
  <div class="empty" role="status">Nothing needs you right now.</div>
{:else}
  <section class="op-alerts" aria-label="Needs attention">
    {#each items as item (item.machine + item.message)}
      <div class="op-alert {item.kind === 'offline' ? 'critical' : ''}"><b>{item.machine}: {item.message}</b><p>{item.fix}</p></div>
    {/each}
  </section>
{/if}
