<script lang="ts">
  import type { Snippet } from 'svelte'
  import Owl from '../Owl.svelte'
  import Icon from '../Icon.svelte'
  import { CARD_ICONS } from '../../lib/machineIcons.ts'
  import { gpuNote, gpuStrip } from '../../lib/gpuLive.ts'
  import { formatUptime, LIVE_FAST_POLL_MS, needsHelperUpdate, offlineText } from '../../lib/stats.ts'
  import type { GpuLive } from '../../lib/gpuLive.ts'
  import type { MachineStatsReply } from '../../lib/types.ts'

  const REFRESH_SECONDS = LIVE_FAST_POLL_MS / 1000

  /** `actions` sits at the right, after the status note. `gpu` is the machine's card with the same reading's numbers, null for a machine without one. */
  let { reply, failed, now, gpu = null, actions }: { reply: MachineStatsReply | null; failed: boolean; now: number; gpu?: GpuLive | null; actions?: Snippet } = $props()
  /** The machine gives no live numbers: it is off, or its helper is too old. */
  const silent = $derived(reply !== null && (needsHelperUpdate(reply) || reply.state === 'offline'))
  const note = $derived(gpu === null ? null : gpuNote(gpu))
</script>

<div class="head">
  <h2>Right now</h2>
  <div class="right">
    {#if silent}<Owl name="offline" />{/if}
    {#if !reply}
      <span class="note" role="status">{failed ? 'Cannot reach the parent.' : 'Reading the machine…'}</span>
    {:else if needsHelperUpdate(reply)}
      <span class="note warn" role="status">This machine's helper is too old to report live numbers. Update the helper on it.</span>
    {:else if reply.state === 'offline'}
      <span class="note warn" role="status">{offlineText(reply, now)}{reply.stats ? ': these are the last numbers' : ''}</span>
    {:else if failed}
      <span class="note warn" role="status">Cannot reach the parent. Showing the last numbers.</span>
    {:else if reply.stats}
      <span class="note nums">{reply.stats.measuring ? 'measuring… · ' : ''}up {formatUptime(reply.stats.uptime_seconds)}</span>
      <span class="caption nums" data-testid="live-caption">live · refreshes every {REFRESH_SECONDS} s</span>
    {/if}
    {#if actions}{@render actions()}{/if}
  </div>
</div>

{#if gpu !== null}
  <div class="gpu" data-testid="gpu-strip">
    <span class="strip nums"><Icon path={CARD_ICONS.gpu} />{gpuStrip(gpu)}</span>
    {#if note !== null}<span class="gap" data-testid="gpu-note">{note}</span>{/if}
  </div>
{/if}

<style>
  .head { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
  .right { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  h2 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .note { font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .caption { font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .note.warn { color: var(--warn); }
  /* The card's four numbers, then the plain sentence for the gap between what was booked and what is really held. */
  .gpu { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; padding: 8px 12px; border: 1px solid var(--line); background: var(--surface-2); }
  .strip { display: inline-flex; align-items: center; gap: 6px; font-family: var(--mono); font-size: 12px; color: var(--text); }
  .gap { font-family: var(--mono); font-size: 11px; color: var(--m50); }
</style>
