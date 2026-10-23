<script lang="ts">
  // "Instance size": Small, Medium, Large and Custom in a select. A preset the machine cannot hold is disabled with the reason in brackets; Custom opens the three number boxes right below.
  import { sizeOptions } from '../../../lib/createSelects.ts'
  import { SIZE_PRESETS, type SizeCard, type SizeKey } from '../../../lib/vmSize.ts'
  import type { WorkloadForm } from '../../../lib/types.ts'
  import FieldBlock from './FieldBlock.svelte'
  import SelectBox from './SelectBox.svelte'

  interface Props {
    id: string
    cards: SizeCard[]
    chosen: SizeKey
    /** The form whose CPU, RAM and disk the Custom boxes edit, and the presets fill in. */
    form: WorkloadForm
    onpick: (key: SizeKey) => void
  }

  let { id, cards, chosen, form = $bindable(), onpick }: Props = $props()

  /** A preset puts its numbers in the form (so Custom, picked next, starts from them); Custom keeps what is there. */
  function pick(value: string) {
    const preset = SIZE_PRESETS.find((entry) => entry.key === value)
    if (preset) Object.assign(form, { cpu: preset.cpu, ramGb: preset.ramGb, diskGb: preset.diskGb })
    onpick(preset ? preset.key : 'custom')
  }
</script>

<FieldBlock label="Instance size" forId={id}>
  <SelectBox {id} value={chosen} options={sizeOptions(cards)} strong onpick={pick} />
  {#if chosen === 'custom'}
    <div class="custom">
      <label>CPU <input type="number" min="1" max="64" step="1" bind:value={form.cpu} /></label>
      <label>RAM (GB) <input type="number" min="0.5" max="1024" step="0.5" bind:value={form.ramGb} /></label>
      <label>Disk (GB) <input type="number" min="1" max="100000" step="1" bind:value={form.diskGb} /></label>
    </div>
  {/if}
</FieldBlock>

<style>
  .custom { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
  label { display: grid; gap: 4px; font: 700 10px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--m50); min-width: 0; }
  input { min-width: 0; min-height: 40px; padding: 0 10px; border: 1px solid var(--reserve-line); border-radius: 0; background: var(--surface); color: var(--text); font: 400 14px var(--mono); }
  input:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; border-color: var(--line-strong); }
  @media (max-width: 520px) { .custom { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
</style>
