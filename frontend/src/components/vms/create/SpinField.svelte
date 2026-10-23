<script lang="ts">
  // A number row of the Create VM window, as in Proxmox: the box with small up and down arrows on its right. The arrows step the number within min and max;
  // the keyboard's arrow keys do the same inside the box, so the arrows are left out of the tab order. A box that cannot be changed says why on hover.
  import FieldBlock from './FieldBlock.svelte'
  import type { FormNumber } from '../../../lib/types.ts'

  interface Props {
    id: string
    label: string
    value: FormNumber
    min: number
    max: number
    step?: number
    disabled?: boolean
    /** Shown while the box is empty, such as "unlimited". */
    placeholder?: string
    /** Why the box cannot be changed; null when it can. */
    reason?: string | null
    oninput: (value: string) => void
  }

  let { id, label, value, min, max, step = 1, disabled = false, placeholder, reason = null, oninput }: Props = $props()
  let input: HTMLInputElement | undefined = $state()

  /** One step up or down, kept inside min and max; an empty box starts from min. */
  function stepBy(direction: 1 | -1) {
    if (!input || disabled) return
    if (input.value === '') input.value = String(min)
    else if (direction > 0) input.stepUp()
    else input.stepDown()
    oninput(input.value)
  }
</script>

<FieldBlock {label} forId={id}>
  <div class="spin" class:disabled title={reason ?? undefined}>
    <input bind:this={input} {id} type="number" inputmode="decimal" {min} {max} {step} {disabled} {placeholder} value={value ?? ''} oninput={(event) => oninput(event.currentTarget.value)} />
    <span class="arrows">
      <button type="button" tabindex="-1" aria-label="Up" {disabled} onclick={() => stepBy(1)}><svg viewBox="0 0 10 6" aria-hidden="true"><path d="M1 5l4-4 4 4" /></svg></button>
      <button type="button" tabindex="-1" aria-label="Down" {disabled} onclick={() => stepBy(-1)}><svg viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" /></svg></button>
    </span>
  </div>
</FieldBlock>

<style>
  .spin { position: relative; display: flex; min-width: 0; border: 1px solid var(--reserve-line); background: var(--surface); }
  .spin:hover:not(.disabled) { border-color: var(--m50); }
  .spin:focus-within { outline: 2px solid var(--accent-mark); outline-offset: 1px; border-color: var(--line-strong); }
  .spin.disabled { background: var(--surface-2); }
  input { flex: 1; min-width: 0; min-height: 30px; padding: 0 9px; border: 0; background: transparent; color: var(--text); font: 400 13px var(--sans); appearance: textfield; -moz-appearance: textfield; }
  input::-webkit-outer-spin-button, input::-webkit-inner-spin-button { -webkit-appearance: none; margin: 0; }
  input:focus { outline: none; }
  input::placeholder { color: var(--m50); }
  input:disabled { color: var(--m40); cursor: not-allowed; }
  .arrows { display: grid; grid-template-rows: 1fr 1fr; flex: none; width: 20px; border-left: 1px solid var(--line); }
  .arrows button { display: grid; place-items: center; padding: 0; border: 0; background: none; color: var(--m60); }
  .arrows button + button { border-top: 1px solid var(--line); }
  .arrows button:hover:not(:disabled) { background: var(--surface-2); color: var(--text); }
  .arrows button:disabled { color: var(--m40); cursor: not-allowed; }
  svg { width: 8px; height: 5px; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
</style>
