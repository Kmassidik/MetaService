<script lang="ts">
  // The window with the top programs. Its content exists only while it is open, so a closed window draws and fetches nothing.
  import Dialog from '../Dialog.svelte'
  import ProcessTable from './ProcessTable.svelte'
  import type { StatsProcess } from '../../lib/types.ts'

  let { open, processes, onClose }: { open: boolean; processes: StatsProcess[] | null; onClose: () => void } = $props()
</script>

<Dialog {open} title="Top processes" wide {onClose}>
  {#if open}<ProcessTable {processes} {onClose} />{/if}
</Dialog>
