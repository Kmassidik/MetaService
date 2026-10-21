<script lang="ts">
  // The GPU section of a container that was given the machine's GPU. "Check the GPU" looks inside it (read-only) and says what it found, in plain words and with the evidence.
  import { ApiError, checkGpu } from '../../lib/api.ts'
  import { evidence, GPU_HIDDEN_TEXT, GPU_VISIBLE_TEXT, UNREADABLE_TEXT, type GpuCheckAnswer } from '../../lib/gpuCheck.ts'

  let { machineId, workloadId }: { machineId: string; workloadId: string } = $props()
  let busy = $state(false)
  let answer: GpuCheckAnswer | null = $state(null)
  let failure = $state('')

  async function check() {
    busy = true
    failure = ''
    try {
      const found = await checkGpu(machineId, workloadId)
      answer = found
      if (!found) failure = UNREADABLE_TEXT
    } catch (error) {
      answer = null
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      busy = false
    }
  }
</script>

<section class="gpu" aria-labelledby="gpu-heading">
  <h3 id="gpu-heading">GPU</h3>
  <p class="muted">This container shares the machine's GPU. The check only looks: it changes nothing.</p>
  <button class="btn line sm" type="button" disabled={busy} onclick={check}>{busy ? 'Checking…' : 'Check the GPU'}</button>
  <div aria-live="polite" data-gpu-result>
    {#if answer}
      <p class="head" class:ok={answer.gpu_visible} class:no={!answer.gpu_visible}>{answer.gpu_visible ? GPU_VISIBLE_TEXT : GPU_HIDDEN_TEXT}</p>
      <p class="note">{answer.note}</p>
      <p class="evidence">{evidence(answer)}</p>
    {/if}
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
  </div>
</section>

<style>
  .gpu { margin-top: 28px; display: grid; gap: 10px; max-width: 820px; justify-items: start; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  p { margin: 0; }
  .head { font-weight: 700; }
  .head.ok { color: var(--ok); }
  .head.no { color: var(--danger); }
  .evidence { font-family: var(--mono); font-size: 12px; color: var(--m70); overflow-wrap: anywhere; white-space: pre-wrap; max-width: 100%; }
  .bad { color: var(--danger); }
</style>
