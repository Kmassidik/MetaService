<script lang="ts">
  // Ruvio (the chat) on this machine: one switch, off by default. Turning it off keeps its chat data.
  import ActionButton from '../ActionButton.svelte'
  import ActionLine from '../ActionLine.svelte'
  import { lineOf } from '../../lib/action.ts'
  import { ActionState } from '../../lib/action.svelte.ts'
  import { reported, type RuvioView } from '../../lib/environment.ts'
  import type { Ruvio } from '../../lib/types.ts'

  let { ruvio, view, onSwitch, onUpdate, onOpen }: {
    ruvio: Ruvio | null | undefined
    view: RuvioView
    /** Turns Ruvio on or off. Throws the refusal. */
    onSwitch: () => Promise<unknown>
    onUpdate: () => Promise<unknown>
    onOpen: () => void
  } = $props()

  const saving = new ActionState()
  /** Where the switch was pushed to, shown while the request runs; if it fails the switch goes back to what is true. */
  let wanted = $state(false)
  const shownOn = $derived(saving.busy ? wanted : view.on)
  const line = $derived(lineOf({ status: saving.status, message: saving.message }, 'Saved'))

  function flip() {
    if (saving.busy) return
    wanted = !view.on
    void saving.run(onSwitch)
  }
</script>

<div class="line">
  <button class="switch" class:on={shownOn} type="button" role="switch" aria-checked={shownOn} aria-busy={saving.busy} aria-label="Ruvio on this machine" disabled={!view.canToggle || saving.busy} onclick={flip}><span class="knob"></span></button>
  <div class="what">
    <b>Ruvio on this machine: {view.status}</b>
    {#if view.reason}<p class="reason">{view.reason}</p>{/if}
    {#if saving.busy}<span class="saving">Saving…</span>{/if}
    <ActionLine {line} failed={saving.status === 'failed'} />
  </div>
</div>
<dl class="kv">
  <div><dt>Installed version</dt><dd class:missing={!ruvio?.installed}>{ruvio?.installed ?? 'not installed'}</dd></div>
  <div><dt>Pinned version</dt><dd class:missing={!ruvio?.pinned}>{reported(ruvio?.pinned)}</dd></div>
</dl>
<div class="actions">
  {#if view.canOpen}<button class="btn line sm" type="button" onclick={onOpen}>Open chat</button>{/if}
  {#if view.canUpdate}<ActionButton variant="line" small label={`Update to ${ruvio?.pinned}`} busyLabel="Updating…" doneLabel="Updated" onrun={onUpdate} />{/if}
</div>
<p class="note">Turning Ruvio off stops the chat and keeps its chat data. Turning it on again brings the same data back.</p>

<style>
  .line { display: flex; align-items: center; gap: 14px; margin-bottom: 12px; }
  .what { min-width: 0; }
  .what b { font: 700 13px var(--mono); }
  .reason { margin: 2px 0 0; font-size: 12.5px; color: var(--warn); }
  .saving { display: block; margin-top: 2px; font: 11px var(--mono); color: var(--m60); }
  .switch { position: relative; flex: none; width: 46px; height: 26px; padding: 0; border: 1px solid var(--line-strong); background: var(--surface); }
  .switch .knob { position: absolute; top: 3px; left: 3px; width: 18px; height: 18px; background: var(--inverse-bg); transition: transform 0.15s; }
  .switch.on { background: var(--accent-mark); }
  .switch.on .knob { transform: translateX(20px); }
  .switch:disabled { opacity: 0.45; cursor: not-allowed; }
  .switch:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .kv { display: grid; margin: 0; }
  .kv > div { display: grid; grid-template-columns: 160px 1fr; gap: 16px; border-bottom: 1px solid var(--surface-2); padding: 10px 0; }
  .kv dt { font: 11px var(--mono); text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; font-size: 13px; }
  .kv dd.missing { color: var(--m50); }
  .actions { display: flex; gap: 8px; margin-top: 12px; flex-wrap: wrap; }
  .note { margin: 12px 0 0; font-size: 12.5px; color: var(--m60); }
  @media (max-width: 820px) { .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
