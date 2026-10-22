<script lang="ts">
  // The fields every "new VM" form has: name, image, kind and the three sizes. The dialog on a machine's page and the Create VM page both use it, so the fields and their limits are in one place.
  import GpuChoice from '../GpuChoice.svelte'
  import type { KindChoice, NewVmForm } from '../../lib/createVm.ts'
  import type { ImageOption } from '../../lib/images.ts'
  import type { Machine } from '../../lib/types.ts'

  interface Props {
    form: NewVmForm
    /** The id of the name field (the label points to it); each form on the page needs its own. */
    nameId: string
    /** The id of the Image select, for the same reason. */
    imageId: string
    kinds: KindChoice[]
    /** The images the machine offers; the ones it cannot give are disabled. */
    images: ImageOption[]
    /** Plain lines under the Image select: why an image cannot be picked. */
    imageNotes: string[]
    /** What is wrong with the name, or null; marks the name field. */
    nameProblem: string | null
    /** The machine the VM goes to, when one is picked: its GPU decides what the GPU line says. */
    machine?: Machine | undefined
  }

  let { form = $bindable(), nameId, imageId, kinds, images, imageNotes, nameProblem, machine }: Props = $props()
  const pickedImage = $derived(images.find((entry) => entry.id === form.bundle))
</script>

<label for={nameId}>Name</label>
<input id={nameId} bind:value={form.name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" placeholder="build-box" aria-invalid={nameProblem ? 'true' : 'false'} />
<label>Image
  <select id={imageId} bind:value={form.bundle}>{#each images as entry (entry.id)}<option value={entry.id} disabled={entry.disabled}>{entry.label}</option>{/each}</select>
</label>
{#if pickedImage}<p class="muted note">{pickedImage.description}</p>{/if}
{#each imageNotes as note (note)}<p class="muted note">{note}</p>{/each}
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
  input, select { min-width: 0; min-height: 40px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); font-weight: 400; }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .note { margin: 0; font-size: 13px; }
  .sizes { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 10px; }
</style>
