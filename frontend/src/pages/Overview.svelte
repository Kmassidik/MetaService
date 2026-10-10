<script>
  // Overview, as in the MAAS panel: the summary cards, the services behind the panel, and what needs the operator.
  import { attentionItems, overviewCounts } from '../lib/overview.js'

  let { machines, brain, bundles } = $props()
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
  <div class="op-service">
    <span class="tag {brain?.configured ? 'run' : 'warn'}">{brain?.configured ? 'connected' : 'not set up'}</span><b>AI provider</b>
    <span class="muted">{brain?.configured ? `${brain.model} at ${brain.host}` : 'Ruvio answers with a plain message until a provider is set.'}</span>
  </div>
  <div class="op-service">
    <span class="tag {bundles?.pinned ? 'run' : 'warn'}">{bundles?.pinned ? 'pinned' : 'no version pinned'}</span><b>Ruvio chat bundle</b>
    <span class="muted">{bundles?.pinned ? `Version ${bundles.pinned}` : 'Pin a version in Settings before installing the chat.'}</span>
  </div>
</section>
<h2 class="op-subhead">Needs attention</h2>
{#if items.length === 0}
  <div class="empty" role="status">{machines.length === 0 ? 'No machines yet. Add the first one from Machines.' : 'Nothing needs you right now.'}</div>
{:else}
  <section class="op-alerts" aria-label="Needs attention">
    {#each items as item (item.machine + item.message)}
      <div class="op-alert {item.kind === 'offline' ? 'critical' : ''}"><b>{item.machine}: {item.message}</b><p>{item.fix}</p></div>
    {/each}
  </section>
{/if}
