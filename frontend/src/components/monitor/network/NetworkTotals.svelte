<script lang="ts">
  // The four totals of this machine on the Network tab: downloaded and uploaded today and this month, in the Live tab's metric cards. They come from the all-machines
  // usage answers, where this machine's row is picked by its id. The note under them says where the numbers come from.
  import { untrack } from 'svelte'
  import MetricCard from '../MetricCard.svelte'
  import NetworkState from './NetworkState.svelte'
  import { networkUsage } from '../../../lib/api.ts'
  import { pollWhileVisible } from '../../../lib/netPoll.ts'
  import { pollMsOf, type NetRange } from '../../../lib/netRange.ts'
  import { totalsOf, type MachineTotals } from '../../../lib/netTotals.ts'
  import { panelStatusOf } from '../../../lib/netStatus.ts'
  import { formatBytes, type UsageReply } from '../../../lib/usageParse.ts'
  import type { Machine } from '../../../lib/types.ts'

  const NOTE = 'Counted from the helper on this machine (its real network card). Traffic recorded before the helper was updated on 2026-11-14 counts every interface and is too high.'

  let { machine, range }: { machine: Machine; range: NetRange } = $props()
  let today = $state<UsageReply | null>(null)
  let month = $state<UsageReply | null>(null)
  let failed = $state(false)
  let attempt = $state(0)
  const id = $derived(machine.id)
  const totals = $derived<MachineTotals | null>(today !== null && month !== null ? totalsOf(today, month, id) : null)
  const count = $derived(today !== null && month !== null ? (totals === null ? 0 : 1) : null)
  const status = $derived(panelStatusOf(count, failed))

  /** `current` says whether this run is still the one in charge; an answer that arrives after the machine changed is thrown away. */
  async function load(current: () => boolean) {
    try {
      const [nextToday, nextMonth] = await Promise.all([networkUsage('today'), networkUsage('month')])
      if (!current()) return
      today = nextToday
      month = nextMonth
      failed = false
    } catch {
      if (current()) failed = true
    }
  }

  function retry() {
    attempt += 1
  }

  // Asks while the tab is open; a new machine, range or retry starts a new run at once.
  $effect(() => {
    void id
    void range
    void attempt
    return untrack(() => {
      today = null
      month = null
      failed = false
      return pollWhileVisible(pollMsOf(range), load)
    })
  })
</script>

{#if totals}
  <div class="totals" data-testid="network-totals">
    <MetricCard label="Downloaded today"><b class="value nums">{formatBytes(totals.downToday)}</b></MetricCard>
    <MetricCard label="Uploaded today"><b class="value nums">{formatBytes(totals.upToday)}</b></MetricCard>
    <MetricCard label="Downloaded this month"><b class="value nums">{formatBytes(totals.downMonth)}</b></MetricCard>
    <MetricCard label="Uploaded this month"><b class="value nums">{formatBytes(totals.upMonth)}</b></MetricCard>
  </div>
{/if}
<NetworkState {status} onRetry={retry} />
{#if totals}<p class="note">{NOTE}</p>{/if}

<style>
  .totals { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
  .value { font-family: var(--mono); font-size: 18px; color: var(--text); }
  .note { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  @media (max-width: 900px) { .totals { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
</style>
