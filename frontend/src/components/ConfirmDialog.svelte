<script lang="ts">
  // The one red confirm dialog for every delete or remove. It says what goes and what is lost, and the red button does it.
  // While the request runs the dialog stays open and locked (Escape, the backdrop and Cancel do nothing); a refusal shows inside it.
  import { tick, type Snippet } from 'svelte'
  import ActionButton from './ActionButton.svelte'
  import Dialog from './Dialog.svelte'
  import { ActionState } from '../lib/action.svelte.ts'

  interface Props {
    open: boolean
    title: string
    /** One plain sentence: what will be deleted or removed, by name. */
    what: string
    /** What is lost, or what is kept. */
    consequence: string
    /** The red button's verb, for example "Delete VM". */
    confirmLabel: string
    busyLabel?: string
    doneLabel?: string
    /** Does the work. Throw to refuse: the dialog stays open and shows the message. The dialog closes itself when this returns. */
    onconfirm: () => Promise<unknown>
    onClose: () => void
    /** Extra choices between the words and the buttons (for example how to log in). */
    children?: Snippet
    /** False keeps the red button off until the extra choices are complete. */
    ready?: boolean
    /** Keeps the dialog locked from outside, on top of its own busy state. */
    locked?: boolean
  }

  let { open, title, what, consequence, confirmLabel, busyLabel = 'Working…', doneLabel = 'Done', onconfirm, onClose, children, ready = true, locked = false }: Props = $props()
  /** A fresh action each time the dialog opens, so an old failure never shows up on the next one. */
  const action = $derived.by(() => {
    void open
    return new ActionState()
  })
  const lockedNow = $derived(locked || action.busy)
  let cancelButton: HTMLButtonElement | undefined

  /** Cancel gets the focus first: Enter on a freshly opened dialog never deletes anything. */
  $effect(() => {
    if (open) void tick().then(() => cancelButton?.focus())
  })

  async function confirm() {
    await onconfirm()
    onClose()
  }
</script>

<Dialog {open} {title} {onClose} locked={lockedNow} backdropClose>
  <p><strong>{what}</strong> {consequence}</p>
  {@render children?.()}
  <div class="row">
    {#if action.busy}<span class="still" role="status">Still working…</span>{/if}
    <button bind:this={cancelButton} class="btn line" type="button" disabled={lockedNow} onclick={onClose}>Cancel</button>
    <ActionButton {action} variant="danger-solid" label={confirmLabel} {busyLabel} {doneLabel} disabled={!ready} onrun={confirm} />
  </div>
</Dialog>

<style>
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
  .still { margin-right: auto; align-self: center; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
