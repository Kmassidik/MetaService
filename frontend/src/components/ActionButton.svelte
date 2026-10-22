<script lang="ts">
  // A button that runs one action at a time: busy label and spinner while it runs, the plain failure next to it, a short success line.
  // A second click, Enter or Space while it runs sends nothing.
  import { lineOf } from '../lib/action.ts'
  import { ActionState } from '../lib/action.svelte.ts'

  type Variant = 'plain' | 'green' | 'line' | 'danger'

  interface Props {
    label: string
    /** Shown while the request runs, for example "Starting…". */
    busyLabel: string
    /** The small line after a success, for example "Started". */
    doneLabel: string
    onrun: () => Promise<unknown>
    variant?: Variant
    small?: boolean
    disabled?: boolean
    title?: string
    /** Give one in when the page around the button needs to know that it is busy (to keep a dialog open, for example). */
    action?: ActionState
  }

  let { label, busyLabel, doneLabel, onrun, variant = 'plain', small = false, disabled = false, title, action }: Props = $props()
  const own = new ActionState()
  const state = $derived(action ?? own)
  const line = $derived(lineOf({ status: state.status, message: state.message }, doneLabel))
</script>

<span class="abtn">
  <button
    class="btn"
    class:green={variant === 'green'}
    class:line={variant === 'line'}
    class:danger={variant === 'danger'}
    class:sm={small}
    type="button"
    {title}
    disabled={disabled || state.busy}
    aria-busy={state.busy}
    onclick={() => void state.run(onrun)}
  >{#if state.busy}<span class="btn-spin" aria-hidden="true"></span>{busyLabel}{:else}{label}{/if}</button>
  <span class="aline" class:bad={state.status === 'failed'} class:hide={line === ''} role="status" aria-live="polite">{line}</span>
</span>

<style>
  .abtn { display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap; max-width: 100%; }
  .aline { font-family: var(--mono); font-size: 11px; color: var(--m60); overflow-wrap: anywhere; max-width: 280px; }
  .aline.bad { color: var(--danger); }
  .aline.hide { display: none; }
</style>
