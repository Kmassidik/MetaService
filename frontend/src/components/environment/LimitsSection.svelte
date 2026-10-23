<script lang="ts">
  // How much of the machine VMs may use, and whether its GPU is offered to them.
  import FormGrid from './FormGrid.svelte'
  import FieldInput from './FieldInput.svelte'
  import { NUMBER_RULES, type EnvForm, type FormErrors } from '../../lib/environmentForm.ts'

  let { form = $bindable(), errors }: { form: EnvForm; errors: FormErrors } = $props()
</script>

<FormGrid>
  <FieldInput name="ramReserveMb" label={NUMBER_RULES.ramReserveMb.label} numeric bind:value={form.ramReserveMb} error={errors.ramReserveMb} />
  <FieldInput name="diskReserveGb" label={NUMBER_RULES.diskReserveGb.label} numeric bind:value={form.diskReserveGb} error={errors.diskReserveGb} />
  <FieldInput name="ramAllowanceMb" label={NUMBER_RULES.ramAllowanceMb.label} numeric bind:value={form.ramAllowanceMb} error={errors.ramAllowanceMb} />
  <FieldInput name="diskAllowanceGb" label={NUMBER_RULES.diskAllowanceGb.label} numeric bind:value={form.diskAllowanceGb} error={errors.diskAllowanceGb} />
  <FieldInput name="vmMaxRunning" label={NUMBER_RULES.vmMaxRunning.label} numeric bind:value={form.vmMaxRunning} error={errors.vmMaxRunning} />
</FormGrid>
<label class="check"><input type="checkbox" name="allowGpu" bind:checked={form.allowGpu} /> Offer the GPU to VMs</label>

<style>
  .check { display: flex; align-items: center; gap: 8px; margin-top: 16px; font-size: 13px; }
  .check input { width: 16px; height: 16px; accent-color: var(--accent-mark); }
</style>
