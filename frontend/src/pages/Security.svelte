<script lang="ts">
  // Security: who is trying to log in to the machines, what was blocked, and whether the basic settings are safe. Read only. The data comes from the parent
  // (GET /api/security/overview and /events). While the parent has no security API the page lists every machine as "Not watched" and says so; it never invents
  // numbers. The sample-data preview (#/security?preview=1) shows the same page from made-up data under a loud banner.
  import { untrack } from 'svelte'
  import BlockedNow from '../components/security/BlockedNow.svelte'
  import DailyChart from '../components/security/DailyChart.svelte'
  import EventLog from '../components/security/EventLog.svelte'
  import MachinesTable from '../components/security/MachinesTable.svelte'
  import PreviewBanner from '../components/security/PreviewBanner.svelte'
  import SecurityHeader from '../components/security/SecurityHeader.svelte'
  import TopList from '../components/security/TopList.svelte'
  import MetricCard from '../components/monitor/MetricCard.svelte'
  import { chartData } from '../lib/securityChart.ts'
  import { SecurityPageData } from '../lib/securityPage.svelte.ts'
  import { parseSecurityView } from '../lib/securityRoute.ts'
  import { NOT_COLLECTED_BANNER, anyWatched, infoOf, machineRows } from '../lib/securityView.ts'
  import type { Machine } from '../lib/types.ts'

  const SEARCH_PAUSE_MS = 250

  let { machines, route, now }: { machines: Machine[]; route: string; now: number } = $props()
  const data = new SecurityPageData()
  const view = $derived(parseSecurityView(route))
  // Single values, so a change of machine or type in the address does not reload what did not change (the overview follows only the range and the preview switch).
  const preview = $derived(view.preview)
  const range = $derived(view.range)
  /** The sample's own machines in preview, the panel's machines otherwise. */
  const infos = $derived(view.preview ? (data.sampleMachines ?? []) : infoOf(machines))
  const rows = $derived(machineRows(infos, data.overviewPhase === 'ready' ? data.overview : null))
  const watched = $derived(rows.filter((row) => row.watched).map(({ id, name, state }) => ({ id, name, state })))
  const chart = $derived(chartData(data.overview?.daily ?? [], watched, view.range, now))
  const collecting = $derived(data.overviewPhase === 'ready' && anyWatched(rows))
  let typed = $state('')
  let searched = $state('')
  const query = $derived({ range, machine: view.machine, type: view.type, q: searched, cursor: null })

  $effect(() => {
    const asked = { preview, range }
    untrack(() => void data.loadOverview(asked.preview, asked.range))
  })

  $effect(() => {
    const asked = { preview, query }
    untrack(() => void data.loadEvents(asked.preview, asked.query))
  })

  $effect(() => {
    const text = typed
    const timer = setTimeout(() => (searched = text), SEARCH_PAUSE_MS)
    return () => clearTimeout(timer)
  })
</script>

{#if view.preview}<PreviewBanner {view} />{/if}
<SecurityHeader {view} />
{#if data.overviewPhase === 'missing'}
  <p class="banner" role="status" data-testid="not-collected">{NOT_COLLECTED_BANNER}</p>
{:else if data.overviewPhase === 'error'}
  <p class="banner" role="alert" data-testid="load-error">{data.overviewError}</p>
{/if}
<div class="body">
  {#if data.overviewPhase === 'loading'}
    <p class="muted" role="status">Loading security data…</p>
  {:else if data.overviewPhase !== 'error'}
    <MetricCard label="Machines" hint="Every machine the panel knows. A machine marked Not watched has sent no security data yet, so nothing is known about it. A dash is a number nobody counted, not zero.">
      {#if rows.length === 0}
        <p class="none">No machines yet. Add a machine and it will be listed here.</p>
      {:else}
        <MachinesTable {rows} {now} />
      {/if}
    </MetricCard>
  {/if}
  {#if collecting}
    <DailyChart {chart} />
    <BlockedNow rows={data.overview?.blocked_now ?? []} {infos} {now} />
    <div class="pair">
      <TopList label="User names the bots try" hint="The user names failed logins used most in this time range. Attackers guess common names." rows={data.overview?.top_users ?? []} testId="top-users" />
      <TopList label="Addresses attacking most" hint="The addresses with the most failed logins in this time range." rows={data.overview?.top_addresses ?? []} testId="top-addresses" />
    </div>
  {/if}
  {#if data.overviewPhase !== 'loading'}
    <EventLog {data} {infos} {view} bind:text={typed} onMore={() => data.loadMore(view.preview, query)} />
  {/if}
</div>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 18px; }
  .body { min-width: 0; }
  :global(.body > section.tile) { min-width: 0; }
</style>
