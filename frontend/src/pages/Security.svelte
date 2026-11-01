<script lang="ts">
  // Security: who is trying to log in to the machines, what was blocked, and whether the basic settings are safe. Read only. The data comes from the parent
  // (GET /api/security/overview and /events). While the parent has no security API the page lists every machine as "Not watched" and says so; it never invents
  // numbers. The sample-data preview (#/security?preview=1) shows the same page from made-up data under a loud banner.
  import { untrack } from 'svelte'
  import BlockedNow from '../components/security/BlockedNow.svelte'
  import BucketChart from '../components/security/BucketChart.svelte'
  import DailyChart from '../components/security/DailyChart.svelte'
  import EventLog from '../components/security/EventLog.svelte'
  import MachinesTable from '../components/security/MachinesTable.svelte'
  import PreviewBanner from '../components/security/PreviewBanner.svelte'
  import SecurityHeader from '../components/security/SecurityHeader.svelte'
  import TopList from '../components/security/TopList.svelte'
  import MetricCard from '../components/monitor/MetricCard.svelte'
  import { bucketChart } from '../lib/securityBuckets.ts'
  import { chartData } from '../lib/securityChart.ts'
  import { RANGE_PHRASE, bucketMinutesOf, isShortRange } from '../lib/securityRanges.ts'
  import { Pager } from '../lib/pager.svelte.ts'
  import { SecurityPageData } from '../lib/securityPage.svelte.ts'
  import { parseSecurityView } from '../lib/securityRoute.ts'
  import { NOT_COLLECTED_BANNER, anyWatched, infoOf, machineRows, rangeSummary } from '../lib/securityView.ts'
  import { browserZone, makeTimeFormat, type TimeMode } from '../lib/securityTime.ts'
  import type { Machine } from '../lib/types.ts'

  const SEARCH_PAUSE_MS = 250

  /** `localZone` is the viewer's own time zone; it is a prop so a test can fix it. */
  let { machines, route, now, localZone = browserZone(), onChanged = () => {} }: { machines: Machine[]; route: string; now: number; localZone?: string; onChanged?: () => void } = $props()
  // Local or UTC times: kept for this visit to the page only, not stored anywhere.
  let timeMode = $state<TimeMode>('local')
  const time = $derived(makeTimeFormat(timeMode, localZone, now))
  const data = new SecurityPageData()
  const view = $derived(parseSecurityView(route))
  // Single values, so a change of machine or type in the address does not reload what did not change (the overview follows only the range and the preview switch).
  const preview = $derived(view.preview)
  const range = $derived(view.range)
  /** The sample's own machines in preview, the panel's machines otherwise. */
  const infos = $derived(view.preview ? (data.sampleMachines ?? []) : infoOf(machines))
  const rows = $derived(machineRows(infos, data.overviewPhase === 'ready' ? data.overview : null))
  const watched = $derived(rows.filter((row) => row.watched).map(({ id, name, state, os }) => ({ id, name, state, os })))
  const short = $derived(isShortRange(range))
  const phrase = $derived(RANGE_PHRASE[range])
  const summary = $derived(rangeSummary(rows, range))
  const chart = $derived(chartData(data.overview?.daily ?? [], watched, view.range, now))
  const buckets = $derived(bucketChart(data.overview?.buckets ?? [], watched, range, now, time.zone, bucketMinutesOf(data.overview?.bucket_minutes ?? null)))
  const collecting = $derived(data.overviewPhase === 'ready' && anyWatched(rows))
  let typed = $state('')
  let searched = $state('')
  const pager = new Pager('security-events')
  // A new filter starts at the first page again.
  pager.resetWhen(() => [range, view.machine, view.type, searched].join('|'))
  const query = $derived({ range, machine: view.machine, type: view.type, q: searched, page: pager.wanted, page_size: pager.size })

  $effect(() => {
    const asked = { preview, range }
    untrack(() => void data.loadOverview(asked.preview, asked.range))
  })

  $effect(() => {
    const asked = { preview, query }
    untrack(() => void data.loadEvents(asked.preview, asked.query))
  })

  // Rows that disappeared while someone was on a late page: ask for the last page that exists.
  $effect(() => {
    const total = data.total
    const wanted = untrack(() => pager.wanted)
    const last = pager.window(total).page
    if (data.eventsPhase === 'ready' && !data.refreshing && wanted !== last) untrack(() => pager.go(last))
  })

  $effect(() => {
    const text = typed
    const timer = setTimeout(() => (searched = text), SEARCH_PAUSE_MS)
    return () => clearTimeout(timer)
  })
</script>

{#if view.preview}<PreviewBanner {view} />{/if}
<SecurityHeader {view} bind:timeMode />
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
        <MachinesTable {rows} {now} {time} {onChanged} />
      {/if}
    </MetricCard>
  {/if}
  {#if collecting}
    {#if summary}<p class="summary" data-testid="range-summary">{summary}</p>{/if}
    {#if short}<BucketChart chart={buckets} {phrase} zoneLabel={time.label} />{:else}<DailyChart {chart} {phrase} />{/if}
    <BlockedNow rows={data.overview?.blocked_now ?? []} {infos} {now} {time} />
    <div class="pair">
      <TopList label="User names the bots try" hint="The user names failed logins used most in this time range. Attackers guess common names." rows={data.overview?.top_users ?? []} testId="top-users" {phrase} />
      <TopList label="Addresses attacking most" hint="The addresses with the most failed logins in this time range." rows={data.overview?.top_addresses ?? []} testId="top-addresses" {phrase} />
    </div>
  {/if}
  {#if data.overviewPhase !== 'loading'}
    <EventLog {data} {infos} {view} {pager} {time} bind:text={typed} />
  {/if}
</div>

<style>
  .summary { margin: 0; font-size: 13px; color: var(--m60); }
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 18px; }
  .body { min-width: 0; }
  :global(.body > section.tile) { min-width: 0; }
</style>
