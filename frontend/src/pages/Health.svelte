<script>
  // Health & alerts, as in the MAAS panel: what is wrong with a machine, then what happened lately.
  import Activity from '../components/Activity.svelte'
  import { attentionItems } from '../lib/overview.js'

  let { machines, commands, now } = $props()
  const items = $derived(attentionItems(machines))
</script>

<div class="phead"><h1>Health &amp; alerts</h1><span class="crumb">Operator › Health &amp; alerts</span></div>
<h2 class="op-subhead">Active alerts</h2>
{#if items.length === 0}
  <div class="empty" role="status">No alerts. Every machine is online and ready.</div>
{:else}
  <section class="op-alerts" aria-label="Active alerts">
    {#each items as item (item.machine + item.message)}
      <div class="op-alert {item.kind === 'offline' ? 'critical' : ''}"><b>{item.machine}: {item.message}</b><p>{item.fix}</p></div>
    {/each}
  </section>
{/if}
<div class="body"><Activity {commands} {now} /></div>
