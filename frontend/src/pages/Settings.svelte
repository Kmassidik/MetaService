<script lang="ts">
  // Settings, as in the MAAS panel: the AI provider and the Ruvio chat bundle, one page.
  import Brain from '../components/Brain.svelte'
  import Bundles from '../components/Bundles.svelte'
  import type { BrainStatus, BundleOverview } from '../lib/types.ts'

  let { brain, bundles, onTest, onPin, onRollback }: { brain: BrainStatus | null; bundles: BundleOverview | null; onTest: () => Promise<unknown>; onPin: (version: string) => Promise<unknown>; onRollback: () => Promise<unknown> } = $props()
</script>

<div class="phead"><h1>Settings</h1><span class="crumb">Operator › Settings</span></div>
<div class="body stack">
  <Brain status={brain} {onTest} />
  <Bundles overview={bundles} {onPin} {onRollback} />
</div>

<style>
  .stack { display: grid; gap: 32px; }
</style>
