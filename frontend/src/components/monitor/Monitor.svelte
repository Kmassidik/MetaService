<script lang="ts">
  // The Live tab of a machine's page: what the machine is really doing, refreshed every 5 seconds while the browser tab is visible and Live is shown.
  // The charts are full on the first look: the parent's last hour is fetched once, then a point is added from the page's own polling every 10 seconds.
  // The list of programs is fetched and drawn only while its window is open.
  import { untrack } from 'svelte'
  import MonitorHeader from './MonitorHeader.svelte'
  import LiveCards from './LiveCards.svelte'
  import ProcessesModal from './ProcessesModal.svelte'
  import { getMachineHistory, getMachineStats } from '../../lib/api.ts'
  import { appendPoint, DEFAULT_INTERVAL_SECONDS, mergeHistory, pointFromReading, pointsFromHistory, type LivePoint } from '../../lib/liveSeries.ts'
  import { processesFromReply } from '../../lib/processList.ts'
  import { MACHINE_PAGE_POLL_MS, reservedText } from '../../lib/stats.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import type { Machine, MachineStatsReply, StatsProcess } from '../../lib/types.ts'

  const MS_PER_SECOND = 1000
  const HISTORY_FAILED = 'The last hour could not be read, so the charts start from now.'

  /** `active` is false while another tab is shown: nothing is asked for then. */
  let { machine, now, active }: { machine: Machine; now: number; active: boolean } = $props()
  /** The machine's name for the route; a new machine object with the same id must not restart the polling. */
  const id = $derived(machine.id)
  let reply = $state<MachineStatsReply | null>(null)
  let points = $state<LivePoint[]>([])
  let intervalSeconds = $state(DEFAULT_INTERVAL_SECONDS)
  let historyFailed = $state(false)
  let failed = $state(false)
  let listOpen = $state(false)
  let processes = $state<StatsProcess[] | null>(null)
  let historyAsked = false

  /** `current` says whether this polling run is still the one in charge: an answer that arrives after the window opened or closed is thrown away. */
  async function load(withProcesses: boolean, current: () => boolean) {
    try {
      const next = await getMachineStats(id, withProcesses)
      if (!current()) return
      reply = next
      failed = false
      processes = processesFromReply(next, withProcesses)
      remember(next)
    } catch {
      if (current()) failed = true
    }
  }

  /** Only a fresh live reading becomes a chart point, and only one every interval. */
  function remember(next: MachineStatsReply) {
    const point = pointFromReading(next, Math.floor(Date.now() / MS_PER_SECOND))
    if (point) points = appendPoint(points, point, intervalSeconds)
  }

  /** The parent's last hour, once. A live point that arrived first is kept when it is newer. */
  async function loadHistory() {
    if (historyAsked) return
    historyAsked = true
    try {
      const history = await getMachineHistory(id)
      intervalSeconds = history.interval_seconds
      points = mergeHistory(pointsFromHistory(history), points)
    } catch {
      historyFailed = true
    }
  }

  function openList() {
    processes = null
    listOpen = true
  }

  // Asks only while Live is shown. Coming back to Live asks at once; the last numbers wait here meanwhile.
  // Opening or closing the window starts a new run that asks with or without the list of programs.
  $effect(() => {
    if (!active) return
    const withProcesses = listOpen
    return untrack(() => {
      let running = true
      void loadHistory()
      const stop = startPolling(browserEnvironment(), MACHINE_PAGE_POLL_MS, () => load(withProcesses, () => running))
      return () => {
        running = false
        stop()
      }
    })
  })

  const stats = $derived(reply?.stats ?? null)
  const grey = $derived(failed || reply?.state === 'offline')
  const canListPrograms = $derived(reply?.state === 'online' && stats !== null)
</script>

<section class="monitor" aria-label="Live monitor" data-testid="monitor">
  <MonitorHeader {reply} {failed} {now}>
    {#snippet actions()}
      {#if canListPrograms}<button class="btn line sm" type="button" data-testid="processes-button" aria-haspopup="dialog" onclick={openList}>Top processes</button>{/if}
    {/snippet}
  </MonitorHeader>
  {#if historyFailed}<p class="note" role="status">{HISTORY_FAILED}</p>{/if}
  {#if stats}<LiveCards {stats} {points} {intervalSeconds} {grey} />{/if}
  <p class="reserved" data-testid="reserved">{reservedText(machine.workloads)}</p>
</section>

<ProcessesModal open={listOpen} {processes} onClose={() => (listOpen = false)} />

<style>
  .monitor { display: grid; gap: 16px; }
  .note { margin: 0; font-family: var(--mono); font-size: 12px; color: var(--warn); }
  .reserved { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m50); }
</style>
