<script lang="ts">
  // The Monitoring tab. MAAS draws CPU, memory and disk bars from its host monitor; MetaService has no live numbers for a VM, so this keeps the MAAS empty state.
  import { monitoringMessage } from '../../lib/vm.ts'

  let { state }: { state: string } = $props()
</script>

<div class="empty quiet" role="status">{monitoringMessage(state)}</div>

<style>
  .quiet { padding: 40px; }
</style>
