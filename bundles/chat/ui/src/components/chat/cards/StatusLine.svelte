<script>
  import { STATUS_TONE } from './statusLabel.js'
  import StepsToggle from '../steps/StepsToggle.svelte'
  import StepList from '../steps/StepList.svelte'

  // Sits under the last message: what the bot is doing, its steps so far, and Stop.
  let { status, steps = [], thumbnail = '', canStop = false, stopDisabled = false, onStop, onOpenComputer } = $props()
  let stepsOpen = $state(false)
  const stepsId = $props.id()
  const working = $derived(status.tone === STATUS_TONE.working)
  const waiting = $derived(status.tone === STATUS_TONE.waiting)
</script>

<div class="status">
  <div class="status-line" class:problem={status.tone === STATUS_TONE.problem} role="status">
    {#if working || waiting}<span class="pulse" class:waiting aria-hidden="true"></span>{/if}
    <span class="text">{status.text}</span>
    {#if thumbnail}
      <button type="button" class="thumb" aria-label="Open the computer" onclick={onOpenComputer}><img src={thumbnail} alt="" /></button>
    {/if}
    {#if steps.length}<StepsToggle bind:open={stepsOpen} controls={stepsId} />{/if}
    {#if canStop}<button type="button" class="link" disabled={stopDisabled} onclick={onStop}>Stop</button>{/if}
  </div>
  {#if stepsOpen && steps.length}<StepList {steps} id={stepsId} />{/if}
</div>

<style>
  .status { margin: 6px 0 2px; }
  .status-line { display: flex; align-items: center; gap: 8px; color: var(--text-2); font: 400 14px/1.4 var(--font); }
  .status-line.problem { color: var(--danger); }
  .text { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .pulse { width: 8px; height: 8px; flex-shrink: 0; border-radius: var(--radius-pill); background: var(--brand-green-d); animation: pulse 1.4s ease-in-out infinite; }
  .thumb { width: 44px; height: 28px; flex-shrink: 0; padding: 0; overflow: hidden; border: 1px solid var(--hairline); border-radius: 6px; background: var(--page); cursor: pointer; }
  .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .link { padding: 2px 6px; border: 0; border-radius: var(--radius-item); background: transparent; color: var(--text-2); font: 500 var(--fs-preview)/1.4 var(--font); cursor: pointer; }
  .link:hover:not(:disabled) { background: var(--tint-hover); color: var(--text); }
  /* Waiting on you is not progress: a steady amber dot instead of the green pulse. */
  .pulse.waiting { background: var(--warn-text); animation: none; }
  @keyframes pulse { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: .35; transform: scale(.8); } }
  @media (prefers-reduced-motion: reduce) { .pulse { animation: none; } }
</style>
