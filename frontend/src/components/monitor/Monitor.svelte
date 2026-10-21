<script lang="ts">
  // The top of a machine's page: what the machine is really doing, refreshed every 5 seconds while the tab is visible.
  import { untrack } from 'svelte'
  import MonitorHeader from './MonitorHeader.svelte'
  import CpuPanel from './CpuPanel.svelte'
  import MemoryPanel from './MemoryPanel.svelte'
  import DiskPanel from './DiskPanel.svelte'
  import NetworkPanel from './NetworkPanel.svelte'
  import GpuPanel from './GpuPanel.svelte'
  import ProcessList from './ProcessList.svelte'
  import { getMachineStats } from '../../lib/api.ts'
  import { historyPoint, MACHINE_PAGE_POLL_MS, pushHistory, reservedText, type HistoryPoint } from '../../lib/stats.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import type { Machine, MachineStatsReply } from '../../lib/types.ts'

  let { machine, now }: { machine: Machine; now: number } = $props()
  /** The machine's name for the route; a new machine object with the same id must not restart the polling. */
  const id = $derived(machine.id)
  let reply = $state<MachineStatsReply | null>(null)
  let history = $state<HistoryPoint[]>([])
  let failed = $state(false)
  let lastTaken = ''

  async function load() {
    try {
      const next = await getMachineStats(id)
      reply = next
      failed = false
      remember(next)
    } catch {
      failed = true
    }
  }

  /** Only a fresh live reading goes into the history (the parent may hand the same one out twice). */
  function remember(next: MachineStatsReply) {
    if (next.state !== 'online' || !next.stats || next.stats.taken_at === lastTaken) return
    lastTaken = next.stats.taken_at
    history = pushHistory(history, historyPoint(next.stats))
  }

  $effect(() => untrack(() => startPolling(browserEnvironment(), MACHINE_PAGE_POLL_MS, load)))

  const stats = $derived(reply?.stats ?? null)
  const grey = $derived(failed || reply?.state === 'offline')
</script>

<section class="monitor" aria-label="Live monitor" data-testid="monitor">
  <MonitorHeader {reply} {failed} {now} />
  {#if stats}
    <div class="blocks" class:grey data-testid="monitor-numbers">
      <CpuPanel cpu={stats.cpu} history={history.map((point) => point.cpu)} />
      <MemoryPanel memory={stats.memory} history={history.map((point) => point.memory)} />
      <DiskPanel disks={stats.disks} />
      <NetworkPanel network={stats.network} down={history.map((point) => point.down)} up={history.map((point) => point.up)} />
      {#if stats.gpus.length}<GpuPanel gpus={stats.gpus} />{/if}
    </div>
    <div class:grey><ProcessList processes={stats.processes} /></div>
  {/if}
  <p class="reserved" data-testid="reserved">{reservedText(machine.workloads)}</p>
</section>

<style>
  .monitor { display: grid; gap: 18px; padding: 20px 28px; border-bottom: 1px solid var(--gray); }
  .blocks { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 24px; }
  .grey { opacity: 0.45; filter: grayscale(1); }
  .reserved { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  @media (max-width: 820px) { .monitor { padding: 16px; } }
</style>
