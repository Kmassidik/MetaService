<script lang="ts">
  // "On: <machine>" at the top of the window. A machine that cannot take a VM is disabled with its reason; the reasons are also written out under the select, with the machine's own words.
  // Opened from one machine's own page the select lists that machine only and cannot be changed.
  import { unavailableNotes, type MachineChoice } from '../../../lib/createVm.ts'

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
</script>

<div class="on">
  <label for={id}><span aria-hidden="true">On:</span><span class="sr-only">Machine</span></label>
  <select {id} {value} onchange={(event) => onpick(event.currentTarget.value)} disabled={locked}>
    {#if options.length > 1 || value === ''}<option value="">{PLACEHOLDER}</option>{/if}
    {#each options as choice (choice.id)}<option value={choice.id} disabled={choice.disabled}>{choice.label}</option>{/each}
  </select>
</div>
{#each notes as note (note)}<p class="muted note">{note}</p>{/each}

<style>
  .on { display: flex; align-items: center; gap: 10px; }
  label { font: 700 12px var(--mono); }
  select { flex: 1; min-width: 0; min-height: 40px; padding: 0 10px; border: 1px solid var(--line); background: var(--surface); color: var(--text); font: 400 13px var(--mono); }
  .note { margin: 0; font-size: 13px; }
</style>
