<script lang="ts">
  import type { Snippet } from 'svelte'
  import Owl from '../Owl.svelte'
  import Icon from '../Icon.svelte'
  import { CARD_ICONS } from '../../lib/machineIcons.ts'
  import { gbText, gpuNote } from '../../lib/gpuLive.ts'
  import { UNKNOWN } from '../../lib/cardFacts.ts'
  import { formatUptime, LIVE_FAST_POLL_MS, needsHelperUpdate, offlineText } from '../../lib/stats.ts'
  import type { GpuLive } from '../../lib/gpuLive.ts'
  import type { MachineStatsReply } from '../../lib/types.ts'

  const REFRESH_SECONDS = LIVE_FAST_POLL_MS / 1000

  /** `actions` sits at the right, after the status note. `gpu` is the machine's card with the same reading's numbers, null for a machine without one. */
  let { reply, failed, now, gpu = null, actions }: { reply: MachineStatsReply | null; failed: boolean; now: number; gpu?: GpuLive | null; actions?: Snippet } = $props()
  /** The machine gives no live numbers: it is off, or its helper is too old. */
  const silent = $derived(reply !== null && (needsHelperUpdate(reply) || reply.state === 'offline'))
  const note = $derived(gpu === null ? null : gpuNote(gpu))
  const shown = (gb: number | null): string => (gb === null ? UNKNOWN : gbText(gb))
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
    <div class="gpu-title"><Icon path={CARD_ICONS.gpu} /><span class="strip nums">GPU {gpu.name}</span></div>
    <div class="memory-grid" data-testid="gpu-memory-grid">
      <div class="cell free"><span class="label">Free</span><strong class="nums">{shown(gpu.freeGb)}</strong></div>
      <div class="cell"><span class="label">Total</span><strong class="nums">{shown(gpu.totalGb)}</strong></div>
      <div class="cell"><span class="label">Booked</span><strong class="nums">{shown(gpu.bookedGb)}</strong></div>
      <div class="cell"><span class="label">Used externally</span><strong class="nums">{shown(gpu.usedGb)}</strong></div>
    </div>
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
  .gpu { display: grid; grid-template-columns: auto 1fr; align-items: center; gap: 10px 16px; padding: 8px 12px; border: 1px solid var(--line); background: var(--surface-2); }
  .gpu-title { display: flex; align-items: center; gap: 6px; }
  .strip { font-family: var(--mono); font-size: 12px; color: var(--text); }
  .memory-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); border: 1px solid var(--line); background: var(--surface); }
  .cell { display: grid; gap: 2px; padding: 7px 10px; }
  .cell:nth-child(odd) { border-right: 1px solid var(--line); }
  .cell:nth-child(-n+2) { border-bottom: 1px solid var(--line); }
  .label { font-family: var(--mono); font-size: 9px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  .cell strong { font-size: 14px; font-weight: 700; }
  .cell.free strong { color: var(--accent-mark); font-size: 18px; }
  .gap { font-family: var(--mono); font-size: 11px; color: var(--m50); }
  @media (max-width: 900px) { .gpu { grid-template-columns: minmax(0, 1fr); } }
  @media (max-width: 420px) { .cell { padding: 6px 8px; } .cell strong { font-size: 13px; } .cell.free strong { font-size: 16px; } }
</style>
