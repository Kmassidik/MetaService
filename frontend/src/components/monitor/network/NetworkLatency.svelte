<script lang="ts">
  // The Latency card of the Network tab: how fast the control server reaches this machine, drawn by the Live tab's time chart. A failed probe is a gap with a red mark.
  // The 30 day view shows the 7 days the route keeps, and says so under the chart.
  import { untrack } from 'svelte'
  import MetricCard from '../MetricCard.svelte'
  import TimeChart from '../charts/TimeChart.svelte'
  import NetworkState from './NetworkState.svelte'
  import { machineLatency } from '../../../lib/api.ts'
  import { latencyChart } from '../../../lib/chartSeries.ts'
  import type { Latency } from '../../../lib/latencyParse.ts'
  import { pollWhileVisible } from '../../../lib/netPoll.ts'
  import { latencyNoteOf, latencyRangeOf, pollMsOf, windowOf, type NetRange } from '../../../lib/netRange.ts'
  import { panelStatusOf } from '../../../lib/netStatus.ts'
  import type { Machine } from '../../../lib/types.ts'

  let { machine, range }: { machine: Machine; range: NetRange } = $props()
  let latency = $state<Latency | null>(null)
  let failed = $state(false)
  let attempt = $state(0)
  const id = $derived(machine.id)
  const count = $derived(latency === null ? null : latency.points.length)
  const status = $derived(panelStatusOf(count, failed))
  const model = $derived(latency !== null && latency.points.length > 0 ? latencyChart(latency.points) : null)
  const span = $derived(windowOf(latencyRangeOf(range)))
  const note = $derived(latencyNoteOf(range))

  /** `current` says whether this run is still the one in charge; an answer that arrives after the range changed is thrown away. */
  async function load(machineId: string, chosen: NetRange, current: () => boolean) {
    try {
      const next = await machineLatency(machineId, latencyRangeOf(chosen))
      if (!current()) return
      latency = next
      failed = false
    } catch {
      if (current()) failed = true
    }
  }

  function retry() {
    attempt += 1
  }

  // Asks while the tab is open; a new machine, range or retry starts a new run at once, and the old numbers are dropped for a new range.
  $effect(() => {
    void id
    void range
    void attempt
    return untrack(() => {
      latency = null
      failed = false
      return pollWhileVisible(pollMsOf(range), (current) => load(id, range, current))
    })
  })
</script>

<MetricCard label="Latency">
  {#if model && latency}
    <TimeChart model={model} label="Latency" intervalSeconds={latency.intervalSeconds} windowSeconds={span.windowSeconds} windowName={span.windowName} />
  {/if}
  <NetworkState {status} onRetry={retry} />
  {#if note}<p class="note">{note}</p>{/if}
</MetricCard>

<style>
  .note { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m50); }
</style>
