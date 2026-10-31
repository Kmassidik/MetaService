<script lang="ts">
  // The event log: newest first, one page at a time with page numbers (the parent cuts the pages). A successful login by password is highlighted (it should not happen).
  // Every text here comes from a machine or an attacker and is only ever drawn as plain text.
  import EventFilters from './EventFilters.svelte'
  import Pagination from '../Pagination.svelte'
  import MetricCard from '../monitor/MetricCard.svelte'
  import type { Pager } from '../../lib/pager.svelte.ts'
  import type { SecurityPageData } from '../../lib/securityPage.svelte.ts'
  import type { SecurityView } from '../../lib/securityRoute.ts'
  import { EVENT_TYPE_LABELS } from '../../lib/securityTypes.ts'
  import { eventDetailText, eventTimeText, eventTone, isPasswordLogin, nameOf, type MachineInfo } from '../../lib/securityView.ts'

  let { data, infos, view, text = $bindable(), pager }: { data: SecurityPageData; infos: MachineInfo[]; view: SecurityView; text: string; pager: Pager } = $props()
</script>

<MetricCard label="Event log" hint="Failed logins are stored as one row per day, machine, user and address with a count of tries. Blocks, unblocks and successful logins are stored one by one. Times are UTC.">
  <EventFilters {infos} {view} bind:text />
  {#if data.eventsPhase === 'loading'}
    <p class="none" role="status">Loading the log…</p>
  {:else if data.eventsPhase === 'error'}
    <p class="none err-line" role="alert">{data.eventsError}</p>
  {:else if data.eventsPhase === 'missing'}
    <p class="none" role="status" data-testid="log-missing">No events are collected yet.</p>
  {:else if data.events.length === 0}
    <p class="none" role="status" data-testid="log-empty">No events match these filters in this time range.</p>
  {:else}
    <div class="scroll" aria-busy={data.refreshing}>
      <table class="restable stack" data-testid="security-log">
        <thead><tr><th>Time (UTC)</th><th>Machine</th><th>Type</th><th>User</th><th>Address</th><th>Detail</th></tr></thead>
        <tbody>
          {#each data.events as event (event.id)}
            <tr data-type={event.type} data-method={event.method ?? undefined} class:pwd={isPasswordLogin(event)}>
              <td data-label="Time" class="when" title={event.time}>{eventTimeText(event.time)}</td>
              <td data-label="Machine">{nameOf(infos, event.machine)}</td>
              <td data-label="Type"><span class="tag {eventTone(event)}">{EVENT_TYPE_LABELS[event.type]}</span></td>
              <td data-label="User" class="plain">{event.user ?? '–'}</td>
              <td data-label="Address" class="plain">{event.address ?? '–'}</td>
              <td data-label="Detail" class="detail">{eventDetailText(event) || '–'}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    {#if data.eventsError}<p class="none err-line" role="alert">{data.eventsError}</p>{/if}
    <Pagination {pager} total={data.total} label="log events" />
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .err-line { color: var(--danger-ink); }
  .scroll { overflow-x: auto; }
  .plain { font-family: var(--mono); font-size: 12px; overflow-wrap: anywhere; }
  .when { font-family: var(--mono); font-size: 12px; white-space: nowrap; }
  .detail { color: var(--m60); overflow-wrap: anywhere; }
  tr.pwd { background: var(--warn-note-bg); box-shadow: inset 3px 0 0 var(--warn-line); }
  :global(.restable.stack td) { padding: 8px 14px; }
  @media (max-width: 820px) { :global(.restable.stack tbody td) { padding: 3px 6px; } }
</style>
