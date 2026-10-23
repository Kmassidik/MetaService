<script lang="ts">
  // The GPU line of the new-VM form. A machine with an NVIDIA card always gets the select: "GPU in a container" can be picked only when containers can use the card, and the line under the select says why when it cannot (a VM, or a missing toolkit).
  // The select also lists the modes that are planned; they are shown disabled and never sent.
  import FieldBlock from './vms/create/FieldBlock.svelte'
  import SelectBox from './vms/create/SelectBox.svelte'
  import { gpuLines, gpuModeToSend, gpuNote, gpuOffer } from '../lib/gpuChoice.ts'
  import { machineHref } from '../lib/routes.ts'
  import type { Machine, WorkloadForm } from '../lib/types.ts'

  const SELECT_ID = 'vm-create-gpu'

  let { form = $bindable(), machine }: { form: WorkloadForm; machine: Machine | undefined } = $props()
  const offer = $derived(gpuOffer(machine, form.kind))
  const options = $derived(gpuLines(offer).map(({ value, label, disabled }) => ({ value, label, disabled })))

  // A changed kind or machine can take the choice away: then the GPU is not asked for.
  $effect(() => {
    const allowed = gpuModeToSend(offer, form.gpuMode)
    if (allowed !== (form.gpuMode ?? 'none')) form.gpuMode = allowed
  })
</script>

{#if offer.show !== 'nothing'}
  <FieldBlock label="GPU acceleration" forId={SELECT_ID}>
    <SelectBox id={SELECT_ID} value={form.gpuMode ?? 'none'} {options} describedBy="{SELECT_ID}-caption" onpick={(mode) => (form.gpuMode = gpuModeToSend(offer, mode))} />
    <p class="note" id="{SELECT_ID}-caption" data-gpu-note={offer.show}>
      {gpuNote(offer, form.gpuMode)}{#if offer.show === 'needs_toolkit' && machine}. <a href={machineHref(machine.id)}>Open the machine's page</a> to see how.{/if}
    </p>
  </FieldBlock>
{/if}

<style>
  .note { margin: 0; font-size: 12px; line-height: 1.5; color: var(--m50); }
</style>
