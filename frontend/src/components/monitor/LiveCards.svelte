<script lang="ts">
  // The Live tab as a Grafana-and-btop page: the gauge row on top; then CPU with Memory, System load with Disk speed, Network with the GPU details, the GPU charts (only for a machine with a GPU), and last the disk volumes.
  // Two columns on a wide screen, one column below 900 px. Every block is a bordered card.
  import CpuCard from './charts/CpuCard.svelte'
  import DiskIoCard from './charts/DiskIoCard.svelte'
  import GaugeRow from './charts/GaugeRow.svelte'
  import LoadCard from './charts/LoadCard.svelte'
  import MemoryCard from './charts/MemoryCard.svelte'
  import NetworkCard from './charts/NetworkCard.svelte'
  import DiskPanel from './DiskPanel.svelte'
  import GpuCharts from './charts/GpuCharts.svelte'
  import GpuPanel from './GpuPanel.svelte'
  import type { GpuBooking } from '../../lib/gpuBooking.ts'
  import type { LivePoint } from '../../lib/liveSeries.ts'
  import type { MachineStats } from '../../lib/types.ts'

  let { stats, points, intervalSeconds, grey, booking = null }: { stats: MachineStats; points: readonly LivePoint[]; intervalSeconds: number; grey: boolean; booking?: GpuBooking | null } = $props()
  const hasGpu = $derived(stats.gpus.length > 0)
</script>

<div class="cards" class:grey data-testid="monitor-numbers">
  <GaugeRow {stats} {points} />
  <div class="band" data-testid="band-cpu">
    <CpuCard {points} cpu={stats.cpu} {intervalSeconds} />
    <MemoryCard {points} memory={stats.memory} {intervalSeconds} />
  </div>
  <div class="band" data-testid="band-load">
    <LoadCard {points} {intervalSeconds} />
    <DiskIoCard {points} {intervalSeconds} />
  </div>
  <div class="band" class:single={!hasGpu} data-testid="band-network">
    <NetworkCard {points} {intervalSeconds} />
    {#if hasGpu}<GpuPanel gpus={stats.gpus} {booking} />{/if}
  </div>
  {#if hasGpu}<GpuCharts gpus={stats.gpus} {points} {intervalSeconds} />{/if}
  <div class="band single" data-testid="band-volumes"><DiskPanel disks={stats.disks} /></div>
</div>

<style>
  .cards { display: grid; gap: 16px; }
  .band { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; align-items: stretch; }
  .band.single { grid-template-columns: minmax(0, 1fr); }
  .grey { opacity: 0.45; filter: grayscale(1); }
  @media (max-width: 900px) { .band { grid-template-columns: minmax(0, 1fr); } }
</style>
