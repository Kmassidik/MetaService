<script lang="ts">
  // A native select that looks the same in every browser: no native arrow, a small chevron drawn inside, the panel's focus ring.
  // `strong` is the heavier look (2px dark border, bold text) the size select uses.
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
  select { width: 100%; min-width: 0; min-height: 44px; padding: 0 40px 0 12px; appearance: none; border: 1px solid var(--reserve-line); border-radius: 0; background: var(--surface); color: var(--text); font: 600 14px var(--mono); cursor: pointer; text-overflow: ellipsis; }
  select.strong { min-height: 48px; border: 2px solid var(--line-strong); font-weight: 700; }
  select:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; border-color: var(--line-strong); }
  select:disabled { cursor: not-allowed; background: var(--surface-2); color: var(--m40); }
  .chevron { position: absolute; top: 50%; right: 12px; width: 16px; height: 16px; margin-top: -8px; pointer-events: none; color: var(--m60); }
</style>
