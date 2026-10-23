<script lang="ts">
  // The GPU line of the new-VM form. A machine with an NVIDIA card always gets the select: "GPU in a container" can be picked only when containers can use the card, and the line under the select says why when it cannot (a VM, or a missing toolkit).
  // "Shared partition" can be picked when the helper can limit GPU memory and some of the card is still free: then a number field asks for the GB. The planned mode is shown disabled and never sent.
  import GpuMemoryField from './GpuMemoryField.svelte'
  import FieldBlock from './vms/create/FieldBlock.svelte'
  import SelectBox from './vms/create/SelectBox.svelte'
  import { defaultGpuMemory, gpuLines, gpuModeToSend, gpuNote, gpuOffer, sharedPartition } from '../lib/gpuChoice.ts'
  import { machineHref } from '../lib/routes.ts'
  import type { Machine, WorkloadForm } from '../lib/types.ts'

  const SELECT_ID = 'vm-create-gpu'

  let { form = $bindable(), machine }: { form: WorkloadForm; machine: Machine | undefined } = $props()
  const offer = $derived(gpuOffer(machine, form.kind))
  const sharing = $derived(sharedPartition(machine, offer))
  const options = $derived(gpuLines(offer, sharing).map(({ value, label, disabled }) => ({ value, label, disabled })))

  // A changed kind or machine can take the choice away: then the GPU is not asked for.
  $effect(() => {
    const allowed = gpuModeToSend(offer, form.gpuMode, sharing)
    if (allowed !== (form.gpuMode ?? 'none')) form.gpuMode = allowed
  })

  // A shared partition starts at its default number; picking another machine clears the number, so it starts again for the new card.
  $effect(() => {
    if (form.gpuMode === 'shared' && sharing.available && form.gpuMemoryGb === undefined) form.gpuMemoryGb = defaultGpuMemory(sharing.booking)
  })
</script>

{#if offer.show !== 'nothing'}
  <FieldBlock label="GPU" forId={SELECT_ID}>
    <SelectBox id={SELECT_ID} value={form.gpuMode ?? 'none'} {options} describedBy="{SELECT_ID}-caption" onpick={(mode) => (form.gpuMode = gpuModeToSend(offer, mode, sharing))} />
    <p class="note" id="{SELECT_ID}-caption" data-gpu-note={offer.show}>
      {gpuNote(offer, form.gpuMode)}{#if offer.show === 'needs_toolkit' && machine}. <a href={machineHref(machine.id)}>Open the machine's page</a> to see how.{/if}
    </p>
    {#if form.gpuMode === 'shared' && sharing.available}<GpuMemoryField bind:form booking={sharing.booking} />{/if}
  </FieldBlock>
{/if}

<style>
  .note { margin: 0; font-size: 12px; line-height: 1.5; color: var(--m50); }
</style>
