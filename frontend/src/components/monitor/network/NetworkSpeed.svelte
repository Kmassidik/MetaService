<script lang="ts">
  // The Speed card of the Network tab: download and upload over the chosen range, drawn by the Live tab's time chart. The hour comes from the stats history the Live tab
  // reads (every 10 seconds); the longer ranges come from the network series, one point per bucket, with a gap where a bucket had no reading.
  import { untrack } from 'svelte'
  import MetricCard from '../MetricCard.svelte'
  import TimeChart from '../charts/TimeChart.svelte'
  import NetworkState from './NetworkState.svelte'
  import { getMachineHistory, machineNetworkSeries } from '../../../lib/api.ts'
  import { speedChart } from '../../../lib/chartSeries.ts'
  import { pointsFromHistory } from '../../../lib/liveSeries.ts'
  import { pollWhileVisible } from '../../../lib/netPoll.ts'
  import { pollMsOf, windowOf, type NetRange } from '../../../lib/netRange.ts'
  import { seriesFromHistory, withGaps, type NetSeries } from '../../../lib/netSeriesParse.ts'
  import { panelStatusOf } from '../../../lib/netStatus.ts'
  import type { Machine } from '../../../lib/types.ts'

  let { machine, range }: { machine: Machine; range: NetRange } = $props()
  let series = $state<NetSeries | null>(null)
  let failed = $state(false)
  let attempt = $state(0)
  const id = $derived(machine.id)
  const count = $derived(series === null ? null : series.points.length)
  const status = $derived(panelStatusOf(count, failed))
  const model = $derived(series !== null && series.points.length > 0 ? speedChart(series.points) : null)
  const span = $derived(windowOf(range))

  /** The hour from the stats history; a longer range from the network series. Both get a gap where a bucket had no reading. */
  async function fetchSeries(machineId: string, chosen: NetRange): Promise<NetSeries> {
    if (chosen !== '1h') return withGapsIn(await machineNetworkSeries(machineId, chosen))
    const history = await getMachineHistory(machineId)
    return withGapsIn({ range: chosen, bucketSeconds: history.interval_seconds, points: seriesFromHistory(pointsFromHistory(history)) })
  }

  /** The same series with a gap put in wherever a bucket is missing. */
  function withGapsIn(next: NetSeries): NetSeries {
    return { ...next, points: withGaps(next.points, next.bucketSeconds) }
  }

  /** `current` says whether this run is still the one in charge; an answer that arrives after the range changed is thrown away. */
  async function load(machineId: string, chosen: NetRange, current: () => boolean) {
    try {
      const next = await fetchSeries(machineId, chosen)
      if (!current()) return
      series = next
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
      series = null
      failed = false
      return pollWhileVisible(pollMsOf(range), (current) => load(id, range, current))
    })
  })
</script>

<MetricCard label="Speed">
  {#if model}
    <TimeChart model={model} label="Network speed" intervalSeconds={series?.bucketSeconds ?? 0} windowSeconds={span.windowSeconds} windowName={span.windowName} />
  {/if}
  <NetworkState {status} onRetry={retry} />
</MetricCard>
