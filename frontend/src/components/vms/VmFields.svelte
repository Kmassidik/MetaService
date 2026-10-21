<script lang="ts">
  // The fields every "new VM" form has: name, kind and the three sizes. The dialog on a machine's page and the Create VM page both use it, so the fields and their limits are in one place.
  import GpuChoice from '../GpuChoice.svelte'
  import type { KindChoice, NewVmForm } from '../../lib/createVm.ts'
  import type { Machine } from '../../lib/types.ts'

  interface Props {
    form: NewVmForm
    /** The id of the name field (the label points to it); each form on the page needs its own. */
    nameId: string
    kinds: KindChoice[]
    /** What is wrong with the name, or null; marks the name field. */
    nameProblem: string | null
    /** The machine the VM goes to, when one is picked: its GPU decides what the GPU line says. */
    machine?: Machine | undefined
  }

  let { form = $bindable(), nameId, kinds, nameProblem, machine }: Props = $props()
</script>

<label for={nameId}>Name</label>
<input id={nameId} bind:value={form.name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" placeholder="build-box" aria-invalid={nameProblem ? 'true' : 'false'} />
<div class="sizes">
  <label>Kind
    <select bind:value={form.kind}>{#each kinds as entry (entry.kind)}<option value={entry.kind} disabled={entry.disabled}>{entry.label}</option>{/each}</select>
  </label>
  <label>CPU <input type="number" min="1" max="64" step="1" bind:value={form.cpu} /></label>
  <label>RAM (GB) <input type="number" min="0.5" max="1024" step="0.5" bind:value={form.ramGb} /></label>
  <label>Disk (GB) <input type="number" min="1" max="100000" step="1" bind:value={form.diskGb} /></label>
</div>
<GpuChoice bind:form {machine} />

<style>
  label { display: grid; gap: 4px; font-weight: 600; font-size: 14px; min-width: 0; }
  input, select { min-width: 0; min-height: 40px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); font-weight: 400; }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .sizes { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 10px; }
</style>
