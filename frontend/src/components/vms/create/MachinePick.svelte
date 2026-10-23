<script lang="ts">
  // "Host": the machine select, each line "<name> (<what it runs>) — <N>GB free". A machine that cannot take a VM is disabled with its reason in the line.
  // The longer explanations (with the machine's own words) are folded into one collapsed line under the select.
  // Opened from one machine's own page the select lists that machine only and cannot be changed.
  import { unavailableNotes, unavailableSummary, type MachineChoice } from '../../../lib/createVm.ts'
  import FieldBlock from './FieldBlock.svelte'
  import SelectBox from './SelectBox.svelte'

  interface Props {
    id: string
    options: MachineChoice[]
    value: string
    locked: boolean
    onpick: (machine: string) => void
  }

  const PLACEHOLDER = 'Choose a machine'

  let { id, options, value, locked, onpick }: Props = $props()
  const notes = $derived(unavailableNotes(options))
  const lines = $derived([
    ...(options.length > 1 || value === '' ? [{ value: '', label: PLACEHOLDER, disabled: false }] : []),
    ...options.map((choice) => ({ value: choice.id, label: choice.label, disabled: choice.disabled })),
  ])
</script>

<FieldBlock label="Host" forId={id}>
  <SelectBox {id} {value} options={lines} disabled={locked} {onpick} />
  {#if notes.length > 0}
    <details class="why">
      <summary>{unavailableSummary(notes.length)}</summary>
      {#each notes as note (note)}<p>{note}</p>{/each}
    </details>
  {/if}
</FieldBlock>

<style>
  .why { font-size: 12px; color: var(--m50); }
  summary { cursor: pointer; width: fit-content; }
  summary:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  p { margin: 4px 0 0; overflow-wrap: anywhere; }
</style>
