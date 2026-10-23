<script lang="ts">
  // The number under the GPU select while "Shared partition" is picked: how many GB of the card's memory this VM may use. It is checked as it is typed.
  import { freeWholeGb, gpuMemoryHint, gpuMemoryProblem, MIN_LIMIT_GB, OVER_LIMIT_WARNING } from '../lib/gpuChoice.ts'
  import type { GpuBooking } from '../lib/gpuBooking.ts'
  import type { WorkloadForm } from '../lib/types.ts'

  const INPUT_ID = 'vm-create-gpu-memory'
  const PROBLEM_ID = `${INPUT_ID}-problem`
  const HINT_ID = `${INPUT_ID}-hint`

  let { form = $bindable(), booking }: { form: WorkloadForm; booking: GpuBooking } = $props()
  const problem = $derived(gpuMemoryProblem('shared', form.gpuMemoryGb, { available: true, booking }))
</script>

<div class="memory" data-gpu-memory>
  <label for={INPUT_ID}>GPU memory for this VM (GB)</label>
  <input id={INPUT_ID} type="number" inputmode="numeric" step="1" min={MIN_LIMIT_GB} max={freeWholeGb(booking)} bind:value={form.gpuMemoryGb} aria-invalid={problem === null ? 'false' : 'true'} aria-describedby="{HINT_ID} {problem === null ? '' : PROBLEM_ID}" />
  {#if problem !== null}<p class="problem" id={PROBLEM_ID} role="alert" data-gpu-memory-problem>{problem}</p>{/if}
  <p class="hint" id={HINT_ID}>{gpuMemoryHint(booking)}</p>
  <p class="hint">{OVER_LIMIT_WARNING}</p>
</div>

<style>
  .memory { display: grid; gap: 6px; margin-top: 8px; min-width: 0; }
  label { font: 700 11px var(--mono); letter-spacing: .14em; text-transform: uppercase; color: var(--m60); }
  input { min-height: 44px; padding: 0 12px; border: 1px solid var(--reserve-line); border-radius: 0; background: var(--surface); color: var(--text); font: 400 14px var(--mono); min-width: 0; }
  input:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; border-color: var(--line-strong); }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .hint, .problem { margin: 0; font-size: 12px; line-height: 1.5; color: var(--m50); }
  .problem { color: var(--danger); }
</style>
