<script lang="ts">
  // A button that runs one action at a time: busy label and spinner while it runs, the plain failure next to it, a short success line.
  // A second click, Enter or Space while it runs sends nothing.
  import { lineOf } from '../lib/action.ts'
  import { ActionState } from '../lib/action.svelte.ts'
  import ActionLine from './ActionLine.svelte'

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
  const current = $derived(action ?? own)
  /** The words of the press that started the work: the page may change the button's own words while it runs (Start becomes Stop), but the line must still say what was asked. */
  let asked = $state({ busy: '', done: '' })
  const line = $derived(lineOf({ status: current.status, message: current.message }, asked.done))

  function press() {
    if (current.busy) return
    asked = { busy: busyLabel, done: doneLabel }
    void current.run(onrun)
  }
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
    disabled={disabled || current.busy}
    aria-busy={current.busy}
    onclick={press}
  >{#if current.busy}<span class="btn-spin" aria-hidden="true"></span>{asked.busy}{:else}{label}{/if}</button>
  <ActionLine {line} failed={current.status === 'failed'} />
</span>

<style>
  .abtn { display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap; max-width: 100%; }
</style>
