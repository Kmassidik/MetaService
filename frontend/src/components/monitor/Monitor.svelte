<script lang="ts">
  // The Live tab of a machine's page: what the machine is really doing, refreshed every 5 seconds while the browser tab is visible and Live is shown.
  // The list of programs is fetched and drawn only while its window is open.
  import { untrack } from 'svelte'
  import MonitorHeader from './MonitorHeader.svelte'
  import LiveCards from './LiveCards.svelte'
  import ProcessesModal from './ProcessesModal.svelte'
  import { getMachineStats } from '../../lib/api.ts'
  import { processesFromReply } from '../../lib/processList.ts'
  import { historyPoint, MACHINE_PAGE_POLL_MS, pushHistory, reservedText, type HistoryPoint } from '../../lib/stats.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import type { Machine, MachineStatsReply, StatsProcess } from '../../lib/types.ts'

  /** `active` is false while another tab is shown: nothing is asked for then. */
  let { machine, now, active }: { machine: Machine; now: number; active: boolean } = $props()
  /** The machine's name for the route; a new machine object with the same id must not restart the polling. */
  const id = $derived(machine.id)
  let reply = $state<MachineStatsReply | null>(null)
  let history = $state<HistoryPoint[]>([])
  let failed = $state(false)
  let listOpen = $state(false)
  let processes = $state<StatsProcess[] | null>(null)
  let lastTaken = ''

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

  /** Only a fresh live reading goes into the history (the parent may hand the same one out twice). */
  function remember(next: MachineStatsReply) {
    if (next.state !== 'online' || !next.stats || next.stats.taken_at === lastTaken) return
    lastTaken = next.stats.taken_at
    history = pushHistory(history, historyPoint(next.stats))
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
  {#if stats}<LiveCards {stats} {history} {grey} />{/if}
  <p class="reserved" data-testid="reserved">{reservedText(machine.workloads)}</p>
</section>

<ProcessesModal open={listOpen} {processes} onClose={() => (listOpen = false)} />

<style>
  .monitor { display: grid; gap: 16px; }
  .reserved { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m50); }
</style>
