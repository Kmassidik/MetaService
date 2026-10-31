<script lang="ts">
  // The record of who made this VM, as the parent kept it: who, which AI client, which token, from where and when. A record that no longer matches its seal is shown in red.
  import { onMount } from 'svelte'
  import { ApiError, workloadOrigin } from '../../lib/api.ts'
  import { ALTERED_TEXT, BACKFILLED_NOTE, originRows, type VmOrigin } from '../../lib/vmOrigin.ts'
  import { UnreadableAnswer } from '../../lib/unreadable.ts'

  let { machineId, workloadId }: { machineId: string; workloadId: string } = $props()
  let origin = $state<VmOrigin | null>(null)
  let loaded = $state(false)
  let failure = $state('')

  onMount(async () => {
    try {
      origin = await workloadOrigin(machineId, workloadId)
    } catch (error) {
      failure = error instanceof ApiError ? error.message : error instanceof UnreadableAnswer ? 'The record could not be read.' : 'Something went wrong.'
    } finally {
      loaded = true
    }
  })
</script>

<section class="origin" aria-labelledby="origin-heading" data-testid="vm-origin">
  <h3 id="origin-heading">Origin</h3>
  {#if !loaded}
    <p class="muted" role="status">Reading the record…</p>
  {:else if failure}
    <p class="bad" role="alert">{failure}</p>
  {:else if origin === null}
    <p class="muted" data-testid="origin-unknown">Unknown origin. The parent has no record of who made this VM.</p>
  {:else}
    <dl class="kv">
      {#each originRows(origin) as row (row.label)}
        <div><dt>{row.label}</dt><dd class="mono">{row.value}</dd></div>
      {/each}
    </dl>
    {#if origin.backfilled}<p class="muted" data-testid="origin-backfilled">{BACKFILLED_NOTE}</p>{/if}
    {#if !origin.intact}<p class="bad altered" role="alert" data-testid="origin-altered">{ALTERED_TEXT}: the stored record does not match its seal. Do not trust it.</p>{/if}
  {/if}
</section>

<style>
  .origin { margin-top: 28px; display: grid; gap: 10px; max-width: 820px; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  p { margin: 0; font-size: 13px; }
  .muted { color: var(--m60); }
  .bad { color: var(--danger); }
  .altered { font-weight: 700; padding: 8px 12px; border: 1px solid var(--danger-line); }
  .kv { display: grid; gap: 14px; margin: 0; }
  .kv > div { display: grid; grid-template-columns: 120px 1fr; align-items: center; gap: 16px; border-bottom: 1px solid var(--surface-2); padding-bottom: 12px; }
  .kv dt { font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; overflow-wrap: anywhere; }
  @media (max-width: 820px) { .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
