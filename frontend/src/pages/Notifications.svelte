<script lang="ts">
  // Notifications: what finished, failed, timed out or lost contact for the jobs this person started, newest first, one page at a time (the parent cuts the pages).
  // A click on Open goes to the VM or machine and marks the row read. Times are in the viewer's zone or UTC (the Local | UTC switch).
  import { untrack } from 'svelte'
  import NotificationRow from '../components/notifications/NotificationRow.svelte'
  import Pagination from '../components/Pagination.svelte'
  import { NOTIFICATIONS_PAGE_SIZE } from '../lib/notifications.ts'
  import { NotificationsData } from '../lib/notificationsPage.svelte.ts'
  import { bell } from '../lib/notificationsStore.svelte.ts'
  import { Pager } from '../lib/pager.svelte.ts'
  import { browserZone, makeTimeFormat, TIME_MODES, TIME_MODE_LABELS, type TimeMode } from '../lib/securityTime.ts'

  /** `localZone` is the viewer's own time zone; it is a prop so a test can fix it. */
  let { now, localZone = browserZone() }: { now: number; localZone?: string } = $props()
  let timeMode = $state<TimeMode>('local')
  const time = $derived(makeTimeFormat(timeMode, localZone, now))
  const data = new NotificationsData()
  const pager = new Pager('notifications', NOTIFICATIONS_PAGE_SIZE)

  $effect(() => {
    const asked = { page: pager.wanted, size: pager.size }
    untrack(() => void data.load(asked.page, asked.size))
  })

  // Rows that disappeared while someone was on a late page: ask for the last page that exists.
  $effect(() => {
    const total = data.total
    const wanted = untrack(() => pager.wanted)
    const last = pager.window(total).page
    if (data.phase === 'ready' && wanted !== last) untrack(() => pager.go(last))
  })

  $effect(() => untrack(() => bell.resume()))
</script>

<div class="phead">
  <h1>Notifications</h1><span class="crumb">Operator › Notifications</span>
  <div class="sp">
    <div class="segmented" role="group" aria-label="Time zone of the times" data-testid="time-mode">
      {#each TIME_MODES as mode (mode)}
        <button type="button" class:on={timeMode === mode} aria-pressed={timeMode === mode} data-mode={mode} onclick={() => (timeMode = mode)}>{TIME_MODE_LABELS[mode]}</button>
      {/each}
    </div>
    <button class="btn line sm" type="button" data-testid="mark-all" disabled={data.unread === 0} onclick={() => data.markAll()}>Mark all read</button>
  </div>
</div>
<p class="what">The jobs you started (create, delete, start, stop) and how they ended. {data.unread} unread.</p>

<div class="body">
  {#if data.phase === 'loading'}
    <p class="none" role="status">Loading notifications…</p>
  {:else if data.phase === 'error'}
    <p class="none bad" role="alert">{data.error}</p>
  {:else if data.total === 0}
    <p class="none" role="status" data-testid="notifications-empty">Nothing yet. When a job you started ends, you are told here.</p>
  {:else}
    <ul class="list" data-testid="notifications-list">
      {#each data.rows as item (item.id)}
        <NotificationRow {item} {time} onRead={(row) => data.markOne(row)} />
      {/each}
    </ul>
    {#if data.markError}<p class="none bad" role="alert">{data.markError}</p>{/if}
    <Pagination {pager} total={data.total} label="notifications" />
  {/if}
</div>

<style>
  .what { margin: 0; padding: 12px 28px 0; font-size: 13px; color: var(--m60); }
  .body { padding: 16px 28px 28px; max-width: 920px; }
  .list { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); }
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .none.bad { color: var(--danger-ink); }
  @media (max-width: 820px) { .what { padding: 12px 16px 0; } .body { padding: 16px; } }
</style>
