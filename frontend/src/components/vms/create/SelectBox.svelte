<script lang="ts">
  // A native select that looks the same in every browser: no native arrow, a small chevron drawn inside, the panel's focus ring.
  // `strong` is the heavier text the size select uses.
  import type { SelectOption } from '../../../lib/createSelects.ts'

  interface Props {
    id: string
    value: string
    options: SelectOption[]
    strong?: boolean
    disabled?: boolean
    describedBy?: string
    onpick: (value: string) => void
  }

  let { id, value, options, strong = false, disabled = false, describedBy, onpick }: Props = $props()
</script>

<div class="box">
  <select {id} {value} {disabled} class:strong aria-describedby={describedBy} onchange={(event) => onpick(event.currentTarget.value)}>
    {#each options as option (option.value)}<option value={option.value} disabled={option.disabled} selected={option.value === value}>{option.label}</option>{/each}
  </select>
  <svg class="chevron" viewBox="0 0 20 20" aria-hidden="true"><path d="M5 7.5l5 5 5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
</div>

<style>
  .box { position: relative; min-width: 0; }
  select { width: 100%; min-width: 0; min-height: 32px; padding: 0 32px 0 9px; appearance: none; border: 1px solid var(--reserve-line); border-radius: 0; background: var(--surface); color: var(--text); font: 400 13px var(--sans); cursor: pointer; text-overflow: ellipsis; }
  select.strong { font-weight: 600; }
  select:hover:not(:disabled) { border-color: var(--m50); }
  select:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 1px; border-color: var(--line-strong); }
  select:disabled { cursor: not-allowed; background: var(--surface-2); color: var(--m40); }
  .chevron { position: absolute; top: 50%; right: 9px; width: 14px; height: 14px; margin-top: -7px; pointer-events: none; color: var(--m60); }
</style>
