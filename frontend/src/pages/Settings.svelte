<script>
  // Settings, as in the MAAS panel: the AI provider and the Ruvio chat bundle, one page.
  import Brain from '../components/Brain.svelte'
  import Bundles from '../components/Bundles.svelte'

  let { brain, bundles, onTest, onPin, onRollback } = $props()
</script>

<div class="phead"><h1>Settings</h1><span class="crumb">Operator › Settings</span></div>
<div class="body stack">
  <Brain status={brain} {onTest} />
  <Bundles overview={bundles} {onPin} {onRollback} />
</div>

<style>
  .stack { display: grid; gap: 32px; }
</style>
