<script lang="ts">
  // Traffic: how much each machine received (download) and sent (upload) for a range, and the network's traffic per day as a bar chart. The two
  // blocks load on their own; a failed ask shows "Could not load" in its own block. Both refresh every REFRESH_MS while the tab is visible.
  import { onMount } from 'svelte'
  import { networkUsage, networkUsageDaily } from '../lib/api.ts'
  import { CHART_HEIGHT, CHART_WIDTH, LABEL_ROOM, dayBars, dayLabel, officeTodayStart } from '../lib/usageChart.ts'
  import { DAY_COUNTS, USAGE_RANGES, fillDays, formatBytes, formatRate, formatShare, type DayCount, type MachineUsage, type UsageDay, type UsageRange, type UsageReply } from '../lib/usageParse.ts'

  const REFRESH_MS = 60_000
  const PLOT_BOTTOM = CHART_HEIGHT - LABEL_ROOM
  const DASH = '—'
  const RANGE_LABELS: Record<UsageRange, string> = { today: 'Today', month: 'This month', '30d': 'Last 30 days' }
  const DAY_LABELS: Record<DayCount, string> = { 7: '7 days', 30: '30 days' }
  const EMPTY_NOTE = 'No traffic recorded yet. The server keeps a reading every 10 seconds, so numbers appear within a minute.'

  type Loaded<T> = { state: 'loading' } | { state: 'failed' } | { state: 'ready'; value: T }
  const LOADING = { state: 'loading' } as const
  const FAILED = { state: 'failed' } as const

  let range = $state<UsageRange>('today')
  let dayCount = $state<DayCount>(7)
  let usage = $state<Loaded<UsageReply>>(LOADING)
  let daily = $state<Loaded<UsageDay[]>>(LOADING)
  let usageAsk = 0
  let dailyAsk = 0

  /** Sum of download and upload over a list of machines. */
  function totalOf(machines: MachineUsage[]): number {
    return machines.reduce((sum, machine) => sum + machine.inBytes + machine.outBytes, 0)
  }

  /** True when no machine and no total has any traffic, so the table has nothing to show. */
  function isSilent(reply: UsageReply): boolean {
    return reply.totalIn + reply.totalOut === 0 && totalOf(reply.machines) === 0
  }

  /** True when every day on the chart has no traffic. */
  function isBlank(days: UsageDay[]): boolean {
    return days.every((day) => day.inBytes === 0 && day.outBytes === 0)
  }

  /** The answer of one ask as a state. A failed ask is a state that says so, never an error that breaks the page. */
  async function settle<T>(ask: () => Promise<T>): Promise<Loaded<T>> {
    try {
      return { state: 'ready', value: await ask() }
    } catch {
      return FAILED
    }
  }

  /** Loads the usage of the range on screen. An answer that arrives after the range changed is dropped. */
  async function loadUsage() {
    const ask = ++usageAsk
    const wanted = range
    const answer = await settle(() => networkUsage(wanted))
    if (ask === usageAsk) usage = answer
  }

  /** Loads the daily traffic and fills the days with no data with zeros. An answer for an old day count is dropped. */
  async function loadDaily() {
    const ask = ++dailyAsk
    const wanted = dayCount
    const answer = await settle(() => networkUsageDaily(wanted))
    if (ask !== dailyAsk) return
    daily = answer.state === 'ready' ? { state: 'ready', value: fillDays(answer.value, wanted, officeTodayStart(Date.now())) } : answer
  }

  /** Shows the loading state, then asks for the usage of the range on screen. */
  function fetchUsage() {
    usage = LOADING
    void loadUsage()
  }

  /** Shows the loading state, then asks for the daily traffic of the day count on screen. */
  function fetchDaily() {
    daily = LOADING
    void loadDaily()
  }

  /** Switches the range shown and asks for it. */
  function chooseRange(option: UsageRange) {
    range = option
    fetchUsage()
  }

  /** Switches the day count shown and asks for it. */
  function chooseDays(option: DayCount) {
    dayCount = option
    fetchDaily()
  }

  /** Loads both blocks again when the tab becomes visible or the timer fires; a hidden tab does not ask. */
  function refreshIfVisible() {
    if (document.hidden) return
    void loadUsage()
    void loadDaily()
  }

  /** The tooltip of one day: its label and the bytes it carried in each direction. */
  function tipOf(day: UsageDay): string {
    return `${dayLabel(day.dayStart, dayCount)}: download ${formatBytes(day.inBytes)}, upload ${formatBytes(day.outBytes)}`
  }

  const machines = $derived(usage.state === 'ready' ? usage.value.machines : [])
  const grandTotal = $derived(totalOf(machines))
  const usageEmpty = $derived(usage.state === 'ready' && isSilent(usage.value))
  const chartDays = $derived(daily.state === 'ready' ? daily.value : [])
  const chartEmpty = $derived(daily.state === 'ready' && isBlank(chartDays))
  const bars = $derived(dayBars(chartDays))

  onMount(() => {
    void loadUsage()
    void loadDaily()
    const timer = setInterval(refreshIfVisible, REFRESH_MS)
    document.addEventListener('visibilitychange', refreshIfVisible)
    return () => {
      clearInterval(timer)
      document.removeEventListener('visibilitychange', refreshIfVisible)
    }
  })
</script>

<section class="traffic">
  <h2>Traffic</h2>
  <p class="muted">What each machine received (download) and sent (upload), counted by the control server.</p>

  <div class="segmented" role="group" aria-label="Traffic range">
    {#each USAGE_RANGES as option (option)}
      <button type="button" class:on={range === option} aria-pressed={range === option} onclick={() => chooseRange(option)}>{RANGE_LABELS[option]}</button>
    {/each}
  </div>

  {#if usage.state === 'loading'}
    <p class="muted">Loading...</p>
  {:else if usage.state === 'failed'}
    <div class="retry"><p class="muted">Could not load</p><button class="btn line sm" type="button" onclick={fetchUsage}>Retry</button></div>
  {:else if usageEmpty}
    <p class="muted">{EMPTY_NOTE}</p>
  {:else}
    <div class="table" role="table" aria-label="Traffic of each machine">
      <div class="head" role="row"><span>Machine</span><span>Download</span><span>Upload</span><span>Download peak</span><span>Upload peak</span><span>Share</span></div>
      {#each usage.value.machines as machine, index (index)}
        <div class="row" role="row">
          <span data-label="Machine">{machine.name || machine.machineId}</span>
          <span class="num" data-label="Download">{formatBytes(machine.inBytes)}</span>
          <span class="num" data-label="Upload">{formatBytes(machine.outBytes)}</span>
          <span class="num" data-label="Download peak">{formatRate(machine.inPeakBps)}</span>
          <span class="num" data-label="Upload peak">{formatRate(machine.outPeakBps)}</span>
          <span class="num" data-label="Share">{formatShare(machine.inBytes + machine.outBytes, grandTotal)}</span>
        </div>
      {/each}
      <div class="row total" role="row">
        <span data-label="Machine">All machines</span>
        <span class="num" data-label="Download">{formatBytes(usage.value.totalIn)}</span>
        <span class="num" data-label="Upload">{formatBytes(usage.value.totalOut)}</span>
        <span class="num" data-label="Download peak">{DASH}</span>
        <span class="num" data-label="Upload peak">{DASH}</span>
        <span class="num" data-label="Share">{DASH}</span>
      </div>
    </div>
  {/if}

  <div class="chart-head">
    <h3>Last {DAY_LABELS[dayCount]}</h3>
    <div class="segmented" role="group" aria-label="Chart days">
      {#each DAY_COUNTS as option (option)}
        <button type="button" class:on={dayCount === option} aria-pressed={dayCount === option} onclick={() => chooseDays(option)}>{DAY_LABELS[option]}</button>
      {/each}
    </div>
  </div>

  {#if daily.state === 'loading'}
    <p class="muted">Loading...</p>
  {:else if daily.state === 'failed'}
    <div class="retry"><p class="muted">Could not load</p><button class="btn line sm" type="button" onclick={fetchDaily}>Retry</button></div>
  {:else if chartEmpty}
    <p class="muted">{EMPTY_NOTE}</p>
  {:else}
    <div class="legend"><span><i class="swatch in"></i>Download</span><span><i class="swatch out"></i>Upload</span></div>
    <svg class="chart" viewBox="0 0 {CHART_WIDTH} {CHART_HEIGHT}" role="img" aria-label="Download and upload of each day, last {dayCount} days">
      {#each bars as bar, index (index)}
        <g>
          <title>{tipOf(bar.day)}</title>
          <rect class="in" x={bar.x} y={PLOT_BOTTOM - bar.inHeight} width={bar.width} height={bar.inHeight} />
          <rect class="out" x={bar.outX} y={PLOT_BOTTOM - bar.outHeight} width={bar.width} height={bar.outHeight} />
          <text x={bar.x + bar.width} y={CHART_HEIGHT - 4} text-anchor="middle">{dayLabel(bar.day.dayStart, dayCount)}</text>
        </g>
      {/each}
    </svg>
  {/if}
</section>

<style>
  .traffic { display: grid; gap: 16px; }
  .traffic h2 { margin: 8px 0 0; font-size: 16px; }
  .traffic h3 { margin: 0; font-size: 14px; }
  .retry { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  .table { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
  .head, .row { display: grid; grid-template-columns: minmax(110px, 1fr) 110px 110px 120px 120px 80px; gap: 12px; align-items: center; padding: 10px 16px; }
  .head { background: var(--surface-2); color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600; }
  .row { border-top: 1px solid var(--line); }
  .row.total { font-weight: 700; }
  .num { font-family: var(--mono); font-size: 13px; }
  .chart-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
  .legend { display: flex; gap: 16px; font-size: 12px; color: var(--muted); }
  .swatch { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 6px; }
  .swatch.in, .chart rect.in { fill: var(--chart-blue); }
  .swatch.out, .chart rect.out { fill: var(--chart-orange); }
  .chart { width: 100%; height: auto; display: block; }
  .chart text { fill: var(--muted); font-family: var(--mono); font-size: 11px; }
  @media (max-width: 760px) {
    .head { display: none; }
    .row { grid-template-columns: 1fr 1fr; }
    .row > span[data-label]::before { content: attr(data-label); display: block; color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
  }
</style>
