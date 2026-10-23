<script lang="ts">
  // The small chip next to a VM's status that says how the app (OpenClaw or Hermes) is doing inside it: installing (with a spinner), ready (green) or install failed (red).
  // The failure message is the chip's hover text, and also a visible line under it on a phone, where there is no hover. It is only ever shown as text.
  import type { AppChip } from '../../lib/appInstall.ts'

  let { chip }: { chip: AppChip } = $props()
</script>

<span class="app">
  <span class="tag" class:prog={chip.tone === 'busy'} class:run={chip.tone === 'ok'} class:bad={chip.tone === 'bad'} title={chip.title ?? undefined} data-app-chip={chip.tone}>
    {#if chip.tone === 'busy'}<span class="btn-spin" aria-hidden="true"></span>{/if}{chip.text}
  </span>
  {#if chip.detail}<small class="detail">{chip.detail}</small>{/if}
</span>

<style>
  .app { display: inline-grid; justify-items: start; gap: 2px; max-width: 100%; }
  .tag { white-space: normal; }
  .tag.bad { color: var(--danger-note-text); border-color: var(--danger-note-bar); background: var(--danger-note-bg); }
  .tag :global(.btn-spin) { margin-right: 5px; }
  .detail { display: none; font-size: 11px; color: var(--danger-note-text); overflow-wrap: anywhere; }
  @media (max-width: 820px) { .detail { display: block; } }
</style>
