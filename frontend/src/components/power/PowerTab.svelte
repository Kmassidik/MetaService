<script lang="ts">
  // The Power tab of a machine's page: how many watts it draws now (machine, CPU, GPU, ANE), the watt lines of the last hour, and the CPU core rail's volts and amps.
  // It asks for itself, the way the Live tab does, but only while this tab is open. A machine (or an older helper) that gives no number draws no card, never zeros.
  import { untrack } from 'svelte'
  import TimeChart from '../monitor/charts/TimeChart.svelte'
  import MetricCard from '../monitor/MetricCard.svelte'
  import { getMachineHistory, getMachineStats } from '../../lib/api.ts'
  import { powerTabChart } from '../../lib/powerTabChart.ts'
  import { appendPoint, DEFAULT_INTERVAL_SECONDS, mergeHistory, pointFromReading, pointsFromHistory, type LivePoint } from '../../lib/liveSeries.ts'
  import { pollIntervalMs } from '../../lib/stats.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import type { Machine, MachineStatsReply } from '../../lib/types.ts'

  const MS_PER_SECOND = 1000
  const HISTORY_FAILED = 'The last hour could not be read, so the chart starts from now.'
  const MACHINE_HINT = 'How many watts the whole machine is drawing at this moment, as the helper reads it.'
  const CPU_HINT = 'How many watts the CPU part of the chip is drawing at this moment. A Mac reports the CPU, GPU and ANE draws separately.'
  const GPU_HINT = 'How many watts the graphics chip is drawing at this moment. The caption names its power limit when the machine knows one.'
  const ANE_HINT = 'How many watts the Neural Engine (the chip part that runs machine-learning models) is drawing at this moment.'
  const CHART_HINT = 'The watts of the last hour, one line per part the machine reports. A missing reading is a gap in the line, never zero.'
  const RAIL_HINT = 'The CPU core rail\u2019s voltage and current from the sensors; their product is an estimate of the rail\u2019s watts, not the whole chip\u2019s draw.'
  const NO_LIMIT = null

  let { machine }: { machine: Machine } = $props()
  const id = $derived(machine.id)
  let reply = $state<MachineStatsReply | null>(null)
  let points = $state<LivePoint[]>([])
  let intervalSeconds = $state(DEFAULT_INTERVAL_SECONDS)
  let historyFailed = $state(false)
  let failed = $state(false)
  let historyAsked = false

  const stats = $derived(reply?.stats ?? null)
  const grey = $derived(failed || reply?.state === 'offline')

  /** The newest reading of one number in the points, or null when none of them has it. */
  function newest(pick: (point: LivePoint) => number | null): number | null {
    for (let index = points.length - 1; index >= 0; index -= 1) {
      const value = pick(points[index] as LivePoint)
      if (value !== null) return value
    }
    return null
  }

  const machineWatts = $derived(newest((point) => point.power))
  const cpuWatts = $derived(newest((point) => point.cpuPower))
  const gpuWatts = $derived(newest((point) => point.gpuPower))
  const aneWatts = $derived(newest((point) => point.anePower))
  const coreVoltage = $derived(newest((point) => point.coreVoltage))
  const coreCurrent = $derived(newest((point) => point.coreCurrent))
  const railWatts = $derived(coreVoltage !== null && coreCurrent !== null ? coreVoltage * coreCurrent : null)
  /** The maker's power limit of the first GPU that names one; the GPU card's caption compares against it. */
  const gpuLimit = $derived(stats?.gpus.find((gpu) => gpu.power_limit_watts !== undefined)?.power_limit_watts ?? NO_LIMIT)
  const gpuCaption = $derived(gpuLimit === null ? 'GPU part now' : `of ${Math.round(gpuLimit)} W limit`)

  async function load(current: () => boolean) {
    try {
      const next = await getMachineStats(id, false)
      if (!current()) return
      reply = next
      failed = false
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

  // Asks only while the Power tab is shown; coming back asks at once, and the last numbers wait here meanwhile.
  $effect(() => {
    void id
    return untrack(() => {
      let running = true
      void loadHistory()
      const environment = browserEnvironment()
      const wait = () => pollIntervalMs({ liveTabVisible: true, pageVisible: environment.isVisible(), failed })
      const stop = startPolling(environment, wait, () => load(() => running))
      return () => {
        running = false
        stop()
      }
    })
  })

  const chart = $derived(powerTabChart(points))
</script>

<section class="power" class:grey aria-label="Power" data-testid="power-tab">
  {#if machineWatts !== null || cpuWatts !== null || gpuWatts !== null || aneWatts !== null}
    <section class="card strip" aria-label="Power draw" data-testid="power-strip">
      {#if machineWatts !== null}
        <div class="cell" title={MACHINE_HINT}>
          <h3>Machine</h3>
          <p class="bignum nums" data-testid="power-machine">{machineWatts.toFixed(1)} <small>W</small></p>
          <p class="sub">whole machine now</p>
        </div>
      {/if}
      {#if cpuWatts !== null}
        <div class="cell" title={CPU_HINT}>
          <h3>CPU</h3>
          <p class="bignum nums" data-testid="power-cpu">{cpuWatts.toFixed(1)} <small>W</small></p>
          <p class="sub">CPU part now</p>
        </div>
      {/if}
      {#if gpuWatts !== null}
        <div class="cell" title={GPU_HINT}>
          <h3>GPU</h3>
          <p class="bignum nums" data-testid="power-gpu">{gpuWatts.toFixed(1)} <small>W</small></p>
          <p class="sub">{gpuCaption}</p>
        </div>
      {/if}
      {#if aneWatts !== null}
        <div class="cell" title={ANE_HINT}>
          <h3>ANE</h3>
          <p class="bignum nums" data-testid="power-ane">{aneWatts.toFixed(1)} <small>W</small></p>
          <p class="sub">Neural Engine now</p>
        </div>
      {/if}
    </section>
  {/if}

  {#if chart}
    <MetricCard label="Last hour" hint={CHART_HINT}>
      <TimeChart model={chart} label="Power" {intervalSeconds} />
    </MetricCard>
  {/if}

  {#if coreVoltage !== null || coreCurrent !== null}
    <MetricCard label="CPU core rail" hint={RAIL_HINT}>
      <dl class="rail nums">
        {#if coreVoltage !== null}<div><dt>Voltage</dt><dd data-testid="power-voltage">{coreVoltage.toFixed(1)} V</dd></div>{/if}
        {#if coreCurrent !== null}<div><dt>Current</dt><dd data-testid="power-current">{coreCurrent.toFixed(1)} A</dd></div>{/if}
        {#if railWatts !== null}<div><dt>Power</dt><dd data-testid="power-rail-watts">{railWatts.toFixed(1)} W</dd></div>{/if}
      </dl>
      {#if railWatts !== null}<p class="sub">estimate from the CPU core rail</p>{/if}
    </MetricCard>
  {/if}

  {#if historyFailed && points.length === 0}<p class="note" role="status">{HISTORY_FAILED}</p>{/if}
  {#if !failed && machineWatts === null && cpuWatts === null && gpuWatts === null}
    <p class="note" role="status" data-testid="power-waiting">
      This machine's helper does not report watts yet. Update the helper (Machines list, or the Environment tab) and wait about two minutes: the first reading needs two samples.
    </p>
  {/if}
</section>

<style>
  .power { display: grid; grid-template-columns: 1fr; gap: 16px; align-items: start; }
  .power > :global(.tile), .note { grid-column: 1 / -1; }
  .strip { padding: 14px 16px; display: flex; flex-wrap: wrap; gap: 8px 48px; }
  .cell { display: grid; gap: 4px; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .bignum { margin: 0; font-family: var(--mono); font-size: 40px; font-weight: 700; line-height: 1; }
  .bignum small { font-size: 18px; font-weight: 400; color: var(--m60); }
  .sub { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .rail { margin: 0; display: flex; flex-wrap: wrap; gap: 4px 32px; font-family: var(--mono); }
  .rail > div { display: grid; gap: 2px; }
  .rail dt { font-size: 11px; color: var(--m60); }
  .rail dd { margin: 0; font-size: 20px; font-weight: 700; }
  .note { margin: 0; font-family: var(--mono); font-size: 12px; color: var(--warn); }
  .grey { opacity: 0.45; filter: grayscale(1); }
</style>
