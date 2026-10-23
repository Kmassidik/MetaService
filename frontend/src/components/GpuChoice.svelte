<script lang="ts">
  // The GPU line of the new-VM form. Only a machine with an NVIDIA card gets one: a container can share the card, a VM cannot (yet), and a card the containers cannot reach yet says what is missing.
  // The select also lists the modes that are planned; they are shown disabled and never sent.
  import FieldBlock from './vms/create/FieldBlock.svelte'
  import SelectBox from './vms/create/SelectBox.svelte'
  import { GPU_OPTIONS, gpuCaption, gpuModeToSend, gpuOffer } from '../lib/gpuChoice.ts'
  import { machineHref } from '../lib/routes.ts'
  import type { Machine, WorkloadForm } from '../lib/types.ts'

  const SELECT_ID = 'vm-create-gpu'

  let { form = $bindable(), machine }: { form: WorkloadForm; machine: Machine | undefined } = $props()
  const offer = $derived(gpuOffer(machine, form.kind))
  const options = GPU_OPTIONS.map(({ value, label, disabled }) => ({ value, label, disabled }))

  // A changed kind or machine can take the choice away: then the GPU is not asked for.
  $effect(() => {
    const allowed = gpuModeToSend(offer, form.gpuMode)
    if (allowed !== (form.gpuMode ?? 'none')) form.gpuMode = allowed
  })
</script>

{#if offer.show === 'choice'}
  <FieldBlock label="GPU acceleration" forId={SELECT_ID}>
    <SelectBox id={SELECT_ID} value={form.gpuMode ?? 'none'} {options} describedBy="{SELECT_ID}-caption" onpick={(mode) => (form.gpuMode = gpuModeToSend(offer, mode))} />
    <p class="note" id="{SELECT_ID}-caption">{gpuCaption(form.gpuMode)}</p>
  </FieldBlock>
{:else if offer.show === 'vm_text'}
  <FieldBlock label="GPU acceleration"><p class="note" data-gpu-note="vm">{offer.text}</p></FieldBlock>
{:else if offer.show === 'needs_toolkit' && machine}
  <FieldBlock label="GPU acceleration"><p class="note" data-gpu-note="toolkit">{offer.text}. <a href={machineHref(machine.id)}>Open the machine's page</a> to see how.</p></FieldBlock>
{/if}

<style>
  .note { margin: 0; font-size: 12px; line-height: 1.5; color: var(--m50); }
</style>
