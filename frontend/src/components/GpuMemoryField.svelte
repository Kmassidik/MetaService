<script lang="ts">
  // The number under the GPU select while "Shared partition" is picked: how many GB of the card's memory this VM may use. It is checked as it is typed,
  // and the box never keeps more than the card can still give: the arrows stop at the cap, and a number typed over it is brought back to the cap when the
  // box is left (the sentence under it named the refusal while it was there).
  import { freeWholeGb, gpuMemoryHint, gpuMemoryProblem, MIN_LIMIT_GB, OVER_LIMIT_WARNING, type GpuRoom } from '../lib/gpuChoice.ts'
  import type { GpuBooking } from '../lib/gpuBooking.ts'
  import type { WorkloadForm } from '../lib/types.ts'

  const INPUT_ID = 'vm-create-gpu-memory'
  const PROBLEM_ID = `${INPUT_ID}-problem`
  const HINT_ID = `${INPUT_ID}-hint`

  let { form = $bindable(), booking, room = null }: { form: WorkloadForm; booking: GpuBooking; room?: GpuRoom | null } = $props()
  /** The most whole GB the box may take: the card's honest free memory, or the parent's booking when the machine has not reported. */
  const capGb = $derived(room?.capGb ?? freeWholeGb(booking))
  const problem = $derived(gpuMemoryProblem('shared', form.gpuMemoryGb, { available: true, booking }, room))

  /** Leaving the box with a number over the cap keeps it at the cap, so the number never promises memory the card does not have. */
  function keepWithinCap(): void {
    const value = form.gpuMemoryGb
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= capGb) return
    form.gpuMemoryGb = capGb
  }
</script>

<div class="memory" data-gpu-memory>
  <label for={INPUT_ID}>GPU memory for this VM (GB)</label>
  <input id={INPUT_ID} type="number" inputmode="numeric" step="1" min={MIN_LIMIT_GB} max={capGb} bind:value={form.gpuMemoryGb} onblur={keepWithinCap} aria-invalid={problem === null ? 'false' : 'true'} aria-describedby="{HINT_ID} {problem === null ? '' : PROBLEM_ID}" />
  {#if problem !== null}<p class="problem" id={PROBLEM_ID} role="alert" data-gpu-memory-problem>{problem}</p>{/if}
  <p class="hint" id={HINT_ID}>{gpuMemoryHint(booking, room)}</p>
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
