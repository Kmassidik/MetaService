<script lang="ts">
  // The cards of the Live tab as a grid: CPU and Memory as two wide cards, then Disk, Network and GPU (Disk and Network only, when there is no GPU) as equal smaller cards.
  // Cards in a row are equally tall; below 900 px wide every card is full width in one column.
  import CpuPanel from './CpuPanel.svelte'
  import MemoryPanel from './MemoryPanel.svelte'
  import DiskPanel from './DiskPanel.svelte'
  import NetworkPanel from './NetworkPanel.svelte'
  import GpuPanel from './GpuPanel.svelte'
  import { lowerRowColumns } from '../../lib/liveLayout.ts'
  import type { HistoryPoint } from '../../lib/stats.ts'
  import type { MachineStats } from '../../lib/types.ts'

  let { stats, history, grey }: { stats: MachineStats; history: readonly HistoryPoint[]; grey: boolean } = $props()
  const hasGpu = $derived(stats.gpus.length > 0)
</script>

<div class="cards" class:grey data-testid="monitor-numbers">
  <div class="band upper" data-testid="cards-upper">
    <CpuPanel cpu={stats.cpu} history={history.map((point) => point.cpu)} />
    <MemoryPanel memory={stats.memory} history={history.map((point) => point.memory)} />
  </div>
  <div class="band lower" style:--columns={lowerRowColumns(hasGpu)} data-testid="cards-lower">
    <DiskPanel disks={stats.disks} />
    <NetworkPanel network={stats.network} down={history.map((point) => point.down)} up={history.map((point) => point.up)} />
    {#if hasGpu}<GpuPanel gpus={stats.gpus} />{/if}
  </div>
</div>

<style>
  .cards { display: grid; gap: 16px; }
  .band { display: grid; gap: 16px; align-items: stretch; }
  .upper { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .lower { grid-template-columns: repeat(var(--columns), minmax(0, 1fr)); }
  .grey { opacity: 0.45; filter: grayscale(1); }
  @media (max-width: 900px) {
    .upper, .lower { grid-template-columns: minmax(0, 1fr); }
  }
</style>
