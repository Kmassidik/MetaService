<script lang="ts">
  // What Create a VM fills in on this machine.
  import Section from './Section.svelte'
  import FormGrid from './FormGrid.svelte'
  import FieldInput from './FieldInput.svelte'
  import { NUMBER_RULES, TEXT_RULES, type EnvForm, type FormErrors } from '../../lib/environmentForm.ts'

  let { form = $bindable(), errors }: { form: EnvForm; errors: FormErrors } = $props()
</script>

<Section title="A new VM gets" intro="Create a VM here starts with these sizes.">
  <FormGrid>
    <FieldInput name="vmCpu" label={NUMBER_RULES.vmCpu.label} numeric bind:value={form.vmCpu} error={errors.vmCpu} />
    <FieldInput name="vmRamMb" label={NUMBER_RULES.vmRamMb.label} numeric bind:value={form.vmRamMb} error={errors.vmRamMb} />
    <FieldInput name="vmDiskGb" label={NUMBER_RULES.vmDiskGb.label} numeric bind:value={form.vmDiskGb} error={errors.vmDiskGb} />
    <FieldInput name="vmImage" label={TEXT_RULES.vmImage.label} bind:value={form.vmImage} error={errors.vmImage} />
  </FormGrid>
</Section>
