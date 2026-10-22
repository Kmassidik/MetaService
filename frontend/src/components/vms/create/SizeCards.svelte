<script lang="ts">
  // The SIZE row: Small, Medium, Large and Custom. A preset the machine cannot hold is greyed out with the reason; Custom opens the three number boxes.
  import CardGroup from './CardGroup.svelte'
  import OptionCard from './OptionCard.svelte'
  import { SIZE_PRESETS, type SizeCard, type SizeKey } from '../../../lib/vmSize.ts'
  import type { WorkloadForm } from '../../../lib/types.ts'

  interface Props {
    group: string
    cards: SizeCard[]
    chosen: SizeKey
    /** The form whose CPU, RAM and disk the Custom boxes edit, and the presets fill in. */
    form: WorkloadForm
    onpick: (key: SizeKey) => void
  }

  let { group, cards, chosen, form = $bindable(), onpick }: Props = $props()

  /** A preset puts its numbers in the form (so Custom, picked next, starts from them); Custom keeps what is there. */
  function pick(value: string) {
    const preset = SIZE_PRESETS.find((entry) => entry.key === value)
    if (preset) Object.assign(form, { cpu: preset.cpu, ramGb: preset.ramGb, diskGb: preset.diskGb })
    onpick(preset ? preset.key : 'custom')
  }
</script>

<CardGroup label="Size" columns={4}>
  {#each cards as card (card.key)}
    <OptionCard {group} value={card.key} label={card.label} caption={card.caption} reason={card.reason} selected={chosen === card.key} disabled={card.disabled} onpick={pick} />
  {/each}
</CardGroup>
{#if chosen === 'custom'}
  <div class="custom">
    <label>CPU <input type="number" min="1" max="64" step="1" bind:value={form.cpu} /></label>
    <label>RAM (GB) <input type="number" min="0.5" max="1024" step="0.5" bind:value={form.ramGb} /></label>
    <label>Disk (GB) <input type="number" min="1" max="100000" step="1" bind:value={form.diskGb} /></label>
  </div>
{/if}

<style>
  .custom { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
  label { display: grid; gap: 4px; font: 700 10px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--m50); min-width: 0; }
  input { min-width: 0; min-height: 40px; padding: 0 10px; border: 1px solid var(--line); background: var(--surface); color: var(--text); font: 400 14px var(--mono); }
  @media (max-width: 520px) { .custom { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
</style>
