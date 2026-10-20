<script lang="ts">
  // How the machine is called: its name, labels and notes, its name on the internet, and the AI model Ruvio uses on it.
  import Section from './Section.svelte'
  import FormGrid from './FormGrid.svelte'
  import FieldInput from './FieldInput.svelte'
  import { MAX_LABELS, MAX_NOTES, TEXT_RULES, type EnvForm, type FormErrors } from '../../lib/environmentForm.ts'

  let { form = $bindable(), errors }: { form: EnvForm; errors: FormErrors } = $props()
</script>

<Section title="Names">
  <FormGrid>
    <FieldInput name="name" label="Name" placeholder="" bind:value={form.name} error={errors.name} hint="The id of the machine does not change." />
    <FieldInput name="labels" label="Labels" bind:value={form.labels} error={errors.labels} hint="Up to {MAX_LABELS}, separated by commas." />
    <FieldInput name="subdomain" label={TEXT_RULES.subdomain.label} bind:value={form.subdomain} error={errors.subdomain} hint="Takes effect when the domain is connected." />
    <FieldInput name="aiModel" label={TEXT_RULES.aiModel.label} bind:value={form.aiModel} error={errors.aiModel} hint="The model Ruvio uses on this machine." />
  </FormGrid>
  <div class="notes">
    <label for="env-notes">Notes</label>
    <textarea id="env-notes" name="notes" rows="3" aria-invalid={errors.notes ? 'true' : 'false'} bind:value={form.notes}></textarea>
    {#if errors.notes}<p class="error" role="alert">{errors.notes}</p>{:else}<p class="hint">{form.notes.length} of {MAX_NOTES} characters.</p>{/if}
  </div>
</Section>

<style>
  .notes { display: grid; gap: 6px; margin-top: 16px; }
  label { font: 10px var(--mono); text-transform: uppercase; letter-spacing: 0.12em; color: var(--m50); }
  textarea { width: 100%; resize: vertical; border: 1px solid var(--gray); background: var(--white); color: var(--black); padding: 10px 12px; font: 14px var(--sans); }
  textarea:focus { outline: 2px solid var(--green); outline-offset: -1px; }
  textarea[aria-invalid='true'] { border-color: #c0392b; }
  .error, .hint { margin: 0; font-size: 12px; }
  .error { color: #c0392b; }
  .hint { color: var(--m50); }
</style>
