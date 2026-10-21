<script lang="ts">
  import { formatUptime, MACHINE_PAGE_POLL_MS, needsHelperUpdate, offlineText } from '../../lib/stats.ts'
  import type { MachineStatsReply } from '../../lib/types.ts'

  const REFRESH_SECONDS = MACHINE_PAGE_POLL_MS / 1000

  let { reply, failed, now }: { reply: MachineStatsReply | null; failed: boolean; now: number } = $props()
</script>

<div class="head">
  <h2>Right now</h2>
  {#if !reply}
    <span class="note" role="status">{failed ? 'Cannot reach the parent.' : 'Reading the machine…'}</span>
  {:else if needsHelperUpdate(reply)}
    <span class="note warn" role="status">This machine's helper is too old to report live numbers. Update the helper on it.</span>
  {:else if reply.state === 'offline'}
    <span class="note warn" role="status">{offlineText(reply, now)}{reply.stats ? ': these are the last numbers' : ''}</span>
  {:else if failed}
    <span class="note warn" role="status">Cannot reach the parent. Showing the last numbers.</span>
  {:else if reply.stats}
    <span class="note nums">{reply.stats.measuring ? 'measuring…' : 'live'} · up {formatUptime(reply.stats.uptime_seconds)} · refreshes every {REFRESH_SECONDS} s</span>
  {/if}
</div>

<style>
  .head { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
  h2 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .note { font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .note.warn { color: var(--warn); }
</style>
