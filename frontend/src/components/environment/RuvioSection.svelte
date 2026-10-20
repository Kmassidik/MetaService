<script lang="ts">
  // Ruvio (the chat) on this machine: one switch, off by default. Turning it off keeps its chat data.
  import Section from './Section.svelte'
  import { reported, type RuvioView } from '../../lib/environment.ts'
  import type { Ruvio } from '../../lib/types.ts'

  let { ruvio, view, failure, onSwitch, onUpdate, onOpen }: {
    ruvio: Ruvio | null | undefined
    view: RuvioView
    failure: string
    onSwitch: () => void
    onUpdate: () => void
    onOpen: () => void
  } = $props()
</script>

<Section title="Ruvio" intro="Ruvio is the chat. It is off until you turn it on.">
  <div class="line">
    <button class="switch" class:on={view.on} type="button" role="switch" aria-checked={view.on} aria-label="Ruvio on this machine" disabled={!view.canToggle} onclick={onSwitch}><span class="knob"></span></button>
    <div class="what">
      <b>Ruvio on this machine: {view.status}</b>
      {#if view.reason}<p class="reason">{view.reason}</p>{/if}
    </div>
  </div>
  <dl class="kv">
    <div><dt>Installed version</dt><dd class:missing={!ruvio?.installed}>{ruvio?.installed ?? 'not installed'}</dd></div>
    <div><dt>Pinned version</dt><dd class:missing={!ruvio?.pinned}>{reported(ruvio?.pinned)}</dd></div>
  </dl>
  {#if failure}<p class="failure" role="alert">{failure}</p>{/if}
  <div class="actions">
    {#if view.canOpen}<button class="btn line sm" type="button" onclick={onOpen}>Open chat</button>{/if}
    {#if view.canUpdate}<button class="btn line sm" type="button" onclick={onUpdate}>Update to {ruvio?.pinned}</button>{/if}
  </div>
  <p class="note">Turning Ruvio off stops the chat and keeps its chat data. Turning it on again brings the same data back.</p>
</Section>

<style>
  .line { display: flex; align-items: center; gap: 14px; margin-bottom: 12px; }
  .what { min-width: 0; }
  .what b { font: 700 13px var(--mono); }
  .reason { margin: 2px 0 0; font-size: 12.5px; color: var(--warn); }
  .switch { position: relative; flex: none; width: 46px; height: 26px; padding: 0; border: 1px solid var(--black); background: var(--white); }
  .switch .knob { position: absolute; top: 3px; left: 3px; width: 18px; height: 18px; background: var(--black); transition: transform 0.15s; }
  .switch.on { background: var(--green); }
  .switch.on .knob { transform: translateX(20px); }
  .switch:disabled { opacity: 0.45; cursor: not-allowed; }
  .switch:focus-visible { outline: 2px solid var(--green); outline-offset: 2px; }
  .kv { display: grid; margin: 0; }
  .kv > div { display: grid; grid-template-columns: 160px 1fr; gap: 16px; border-bottom: 1px solid var(--gray2); padding: 10px 0; }
  .kv dt { font: 11px var(--mono); text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; font-size: 13px; }
  .kv dd.missing { color: var(--m50); }
  .failure { margin: 12px 0 0; padding: 10px 12px; border: 1px solid #efc5c1; border-left: 4px solid #b52b22; background: #fff5f4; color: #98281f; font-size: 13px; overflow-wrap: anywhere; }
  .actions { display: flex; gap: 8px; margin-top: 12px; flex-wrap: wrap; }
  .note { margin: 12px 0 0; font-size: 12.5px; color: var(--m60); }
  @media (max-width: 820px) { .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
