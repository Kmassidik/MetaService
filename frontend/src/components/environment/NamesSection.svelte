<script lang="ts">
  // How the machine is called: its name, labels and notes, its name on the internet, the AI model Ruvio uses on it, and the SSH address for the ssh command.
  import FormGrid from './FormGrid.svelte'
  import FieldInput from './FieldInput.svelte'
  import { MAX_LABELS, MAX_NOTES, TEXT_RULES, type EnvForm, type FormErrors } from '../../lib/environmentForm.ts'

  const SSH_JUMP_HINT = "Used for the ssh command in SSH keys. Example: you@203.0.113.7 or you@studio.example.com:2222. Leave empty to use the machine's office address"

  let { form = $bindable(), errors }: { form: EnvForm; errors: FormErrors } = $props()
</script>

<FormGrid>
  <FieldInput name="name" label="Name" placeholder="" bind:value={form.name} error={errors.name} hint="The id of the machine does not change." />
  <FieldInput name="labels" label="Labels" bind:value={form.labels} error={errors.labels} hint="Up to {MAX_LABELS}, separated by commas." />
  <FieldInput name="subdomain" label={TEXT_RULES.subdomain.label} bind:value={form.subdomain} error={errors.subdomain} hint="Takes effect when the domain is connected." />
  <FieldInput name="aiModel" label={TEXT_RULES.aiModel.label} bind:value={form.aiModel} error={errors.aiModel} hint="The model Ruvio uses on this machine." />
  <FieldInput name="sshJump" label={TEXT_RULES.sshJump.label} bind:value={form.sshJump} error={errors.sshJump} hint={SSH_JUMP_HINT} placeholder="you@203.0.113.7" />
</FormGrid>
<div class="notes">
  <label for="env-notes">Notes</label>
  <textarea id="env-notes" name="notes" rows="3" aria-invalid={errors.notes ? 'true' : 'false'} bind:value={form.notes}></textarea>
  {#if errors.notes}<p class="error" role="alert">{errors.notes}</p>{:else}<p class="hint">{form.notes.length} of {MAX_NOTES} characters.</p>{/if}
</div>

<style>
  .notes { display: grid; gap: 6px; margin-top: 16px; }
  label { font: 10px var(--mono); text-transform: uppercase; letter-spacing: 0.12em; color: var(--m50); }
  textarea { width: 100%; resize: vertical; border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 10px 12px; font: 14px var(--sans); }
  textarea:focus { outline: 2px solid var(--accent-mark); outline-offset: -1px; }
  textarea[aria-invalid='true'] { border-color: var(--danger); }
  .error, .hint { margin: 0; font-size: 12px; }
  .error { color: var(--danger); }
  .hint { color: var(--m50); }
</style>
