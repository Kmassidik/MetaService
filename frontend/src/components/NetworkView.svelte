<script lang="ts">
  // Network: how fast the control server reaches each machine, one row per machine, for the range on screen. Each machine is asked in parallel;
  // one failed ask shows "Could not load" in its own row. The numbers refresh every POLL_MS while the tab is visible.
  import { onMount, untrack } from 'svelte'
  import { machineLatency } from '../lib/api.ts'
  import { latencyState, RANGES, type Latency, type LatencyRange, type LatencyState } from '../lib/latencyParse.ts'
  import type { Machine } from '../lib/types.ts'
  import LatencySparkline from './LatencySparkline.svelte'
  import Owl from './Owl.svelte'

  const POLL_MS = 10_000
  const FAILED = 'failed' as const
  const RANGE_LABELS: Record<LatencyRange, string> = { '1h': '1 hour', '24h': '24 hours', '7d': '7 days' }
  const STATE_TAGS: Record<LatencyState, { label: string; tone: string }> = {
    ok: { label: 'Good', tone: 'run' },
    slow: { label: 'Slow', tone: 'warn' },
    down: { label: 'No answer', tone: 'down' },
    none: { label: 'No readings yet', tone: '' },
  }
  const DOWN_NOTE = 'The control server cannot reach any machine right now. Check the network permission for the server on its Mac.'

  type Reading = Latency | typeof FAILED

  let { machines }: { machines: Machine[] } = $props()
  let range = $state<LatencyRange>('1h')
  /** Keyed by machine id. A machine with no entry is still loading. */
  let readings = $state<Record<string, Reading>>({})
  let generation = 0
  const machineKey = $derived(machines.map((machine) => machine.id).join(' '))
  const everyDown = $derived(machines.length > 0 && machines.every((machine) => stateOf(machine.id) === 'down'))

  /** The machine's latency when it loaded, else null. */
  function latencyOf(id: string): Latency | null {
    const reading = readings[id]
    return typeof reading === 'object' ? reading : null
  }

  /** The state of a machine that loaded, else null. */
  function stateOf(id: string): LatencyState | null {
    const latency = latencyOf(id)
    return latency === null ? null : latencyState(latency)
  }

  /** One machine's reading for the range. A failed ask is a reading that says so, so one machine never breaks the page. */
  async function readingOf(id: string, wanted: LatencyRange): Promise<Reading> {
    try {
      return await machineLatency(id, wanted)
    } catch {
      return FAILED
    }
  }

  /** Asks every machine at once for the range on screen. An answer that arrives after the range or the list changed is dropped. */
  async function loadAll() {
    const ask = ++generation
    const wanted = range
    const entries = await Promise.all(machines.map(async (machine) => [machine.id, await readingOf(machine.id, wanted)] as const))
    if (ask !== generation) return
    readings = Object.fromEntries(entries)
  }

  /** Loads again when the tab becomes visible; a hidden tab does not ask. */
  function refreshIfVisible() {
    if (!document.hidden) void loadAll()
  }

  /** Format of a millisecond value, or a dash when there is none. */
  const msText = (value: number | null | undefined) => (value === null || value === undefined ? '—' : `${Math.round(value)} ms`)
  /** Loss in percent with one decimal place. */
  const percentText = (value: number) => `${value.toFixed(1)} %`

  $effect(() => {
    void [range, machineKey]
    untrack(() => void loadAll())
  })

  onMount(() => {
    const timer = setInterval(refreshIfVisible, POLL_MS)
    document.addEventListener('visibilitychange', refreshIfVisible)
    return () => {
      clearInterval(timer)
      document.removeEventListener('visibilitychange', refreshIfVisible)
    }
  })
</script>

<div class="phead"><h1>Network</h1><span class="crumb">Infrastructure › Network</span></div>

<section class="network">
  <p class="muted">How fast the control server reaches each machine (a connection to the machine's helper, measured every 10 seconds).</p>

  <div class="segmented" role="group" aria-label="Time range">
    {#each RANGES as option (option)}
      <button type="button" class:on={range === option} aria-pressed={range === option} onclick={() => (range = option)}>{RANGE_LABELS[option]}</button>
    {/each}
  </div>

  {#if machines.length === 0}
    <div class="none"><Owl name="emptyMachines" /><p class="muted">No machines yet. Add one from Find machines.</p></div>
  {:else}
    {#if everyDown}<p class="note">{DOWN_NOTE}</p>{/if}
    <div class="table" role="table" aria-label="Latency of each machine">
      <div class="head" role="row"><span>Machine</span><span>Address</span><span>Now</span><span>Average</span><span>Worst</span><span>Lost</span><span>Trend</span><span>Status</span></div>
      {#each machines as machine (machine.id)}
        {@const latency = latencyOf(machine.id)}
        {@const failed = readings[machine.id] === FAILED}
        <div class="row" role="row">
          <span data-label="Machine">{machine.name}</span>
          <span class="mono" data-label="Address">{machine.ip ?? '–'}</span>
          <span class="num" data-label="Now">{msText(latency?.summary.lastMs)}</span>
          <span class="num" data-label="Average">{msText(latency?.summary.averageMs)}</span>
          <span class="num" data-label="Worst">{msText(latency?.summary.maxMs)}</span>
          <span class="num" data-label="Lost">{latency ? percentText(latency.summary.percentFailed) : '—'}</span>
          <span class="trend" data-label="Trend">{#if latency}<LatencySparkline points={latency.points} />{/if}</span>
          <span class="status" data-label="Status">
            {#if latency}
              <span class="tag {STATE_TAGS[latencyState(latency)].tone}">{STATE_TAGS[latencyState(latency)].label}</span>
            {:else if failed}
              <span class="muted">Could not load</span>
            {:else}
              <span class="muted">Loading…</span>
            {/if}
          </span>
        </div>
      {/each}
    </div>
  {/if}
</section>

<style>
  .network { display: grid; gap: 16px; padding: 22px 28px; }
  .none { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; text-align: center; min-height: calc(100svh - 300px); }
  .note { padding: 10px 14px; border-radius: 8px; background: var(--warn-bg); color: var(--warn); }
  .table { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
  .head, .row { display: grid; grid-template-columns: minmax(110px, 1fr) 120px 70px 80px 70px 70px minmax(120px, 1.4fr) 130px; gap: 12px; align-items: center; padding: 10px 16px; }
  .head { background: var(--surface-2); color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600; }
  .row { border-top: 1px solid var(--line); }
  .num { font-family: var(--mono); font-size: 13px; }
  .tag.down { color: var(--danger); border-color: var(--danger-line); background: var(--danger-bg); }
  .status { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  @media (max-width: 760px) {
    .head { display: none; }
    .row { grid-template-columns: 1fr 1fr; }
    .row > span[data-label]::before { content: attr(data-label); display: block; color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
    .trend { grid-column: 1 / -1; }
  }
</style>
