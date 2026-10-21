<script lang="ts">
  // The GPU line of the new-VM form. Only a machine with an NVIDIA card gets one: a container can share the card, a VM cannot (yet), and a card the containers cannot reach yet says what is missing.
  import { GPU_EXPLAINED, NO_GPU_LABEL, SHARE_GPU_LABEL, gpuModeToSend, gpuOffer } from '../lib/gpuChoice.ts'
  import { machineHref } from '../lib/routes.ts'
  import type { Machine, WorkloadForm } from '../lib/types.ts'

  let { form = $bindable(), machine }: { form: WorkloadForm; machine: Machine | undefined } = $props()
  const offer = $derived(gpuOffer(machine, form.kind))

  // A changed kind or machine can take the choice away: then the GPU is not asked for.
  $effect(() => {
    const allowed = gpuModeToSend(offer, form.gpuMode)
    if (allowed !== (form.gpuMode ?? 'none')) form.gpuMode = allowed
  })
</script>

{#if offer.show === 'choice'}
  <fieldset class="gpu" aria-label="GPU">
    <legend>GPU</legend>
    <label class="gpu-opt"><input type="radio" name="gpu-mode" value="none" checked={form.gpuMode !== 'container'} onchange={() => (form.gpuMode = 'none')} /> {NO_GPU_LABEL}</label>
    <label class="gpu-opt"><input type="radio" name="gpu-mode" value="container" checked={form.gpuMode === 'container'} onchange={() => (form.gpuMode = 'container')} /> {SHARE_GPU_LABEL} <span class="gpu-card">({offer.card})</span></label>
    <p class="muted note">{GPU_EXPLAINED}</p>
  </fieldset>
{:else if offer.show === 'vm_text'}
  <p class="muted note" data-gpu-note="vm">{offer.text}</p>
{:else if offer.show === 'needs_toolkit' && machine}
  <p class="muted note" data-gpu-note="toolkit">{offer.text}. <a href={machineHref(machine.id)}>Open the machine's page</a> to see how.</p>
{/if}

<style>
  .gpu { display: grid; gap: 6px; border: 1px solid var(--line); border-radius: 8px; padding: 8px 12px 10px; min-width: 0; margin: 0; }
  legend { font-weight: 600; font-size: 14px; padding: 0 4px; }
  .gpu-opt { display: flex; gap: 8px; align-items: baseline; font-weight: 400; font-size: 14px; flex-wrap: wrap; }
  .gpu-card { font-family: var(--mono); font-size: 12px; color: var(--m50); overflow-wrap: anywhere; }
  .note { margin: 0; font-size: 13px; }
</style>
