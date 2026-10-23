<script lang="ts">
  // Renaming a machine: one text box with the rule under it. Only the name changes; the id and every link stay. While the request runs the window stays open and locked;
  // a refusal from the parent ("another machine already has that name") shows inside it.
  import { tick, untrack } from 'svelte'
  import ActionButton from './ActionButton.svelte'
  import Dialog from './Dialog.svelte'
  import { ActionState } from '../lib/action.svelte.ts'
  import { ApiError, updateMachineSettings } from '../lib/api.ts'
  import { MACHINE_NAME_MAX, MACHINE_NAME_RULE, machineNameProblem } from '../lib/format.ts'
  import { RENAME_LABEL } from '../lib/machineIcons.ts'
  import type { Machine } from '../lib/types.ts'

  interface Props {
    machine: Machine | null
    /** The machines changed on the parent: read them again, so the new name shows everywhere. */
    onSaved: () => Promise<void> | void
    onClose: () => void
  }

  let { machine, onSaved, onClose }: Props = $props()
  const INPUT_ID = 'rename-machine-name'
  let name = $state('')
  let input: HTMLInputElement | undefined
  /** A fresh action each time the window opens, so an old refusal never shows up on the next one. */
  const action = $derived.by(() => {
    void machine
    return new ActionState()
  })
  const problem = $derived(machineNameProblem(name))
  const unchanged = $derived(name === machine?.name)
  const canSave = $derived(machine !== null && problem === null && !unchanged && !action.busy)

  $effect(() => {
    if (!machine) return
    const current = machine.name
    untrack(() => (name = current))
    void tick().then(() => input?.select())
  })

  /** Sends only the name. Throws the parent's refusal, which the Save button shows beside itself. */
  async function save() {
    if (!machine) return
    try {
      await updateMachineSettings(machine.id, { name })
    } catch (error) {
      throw error instanceof ApiError ? error : new Error('Something went wrong.')
    }
    await onSaved()
    onClose()
  }

  function submit(event: SubmitEvent) {
    event.preventDefault()
    if (canSave) void action.run(save)
  }
</script>

<Dialog open={machine !== null} title={RENAME_LABEL} {onClose} locked={action.busy} backdropClose>
  <form onsubmit={submit}>
    <label for={INPUT_ID}>Name</label>
    <input id={INPUT_ID} bind:this={input} bind:value={name} autocomplete="off" spellcheck="false" maxlength={MACHINE_NAME_MAX * 2} aria-invalid={problem ? 'true' : 'false'} aria-describedby="rename-machine-hint" />
    <p class="hint" class:bad={problem !== null} id="rename-machine-hint">{problem ?? `${MACHINE_NAME_RULE} The machine's id and links do not change.`}</p>
    <div class="row">
      {#if action.busy}<span class="still" role="status">Still working…</span>{/if}
      <button class="btn line" type="button" disabled={action.busy} onclick={onClose}>Cancel</button>
      <ActionButton {action} variant="green" label="Save" busyLabel="Saving…" doneLabel="Saved" disabled={!canSave} onrun={save} />
    </div>
  </form>
</Dialog>

<style>
  form { display: grid; gap: 8px; }
  label { font: 10px var(--mono); text-transform: uppercase; letter-spacing: 0.12em; color: var(--m50); }
  input { width: 100%; box-sizing: border-box; border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 10px 12px; font: 14px var(--sans); }
  input:focus { outline: 2px solid var(--accent-mark); outline-offset: -1px; }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .hint { margin: 0; font-size: 12px; color: var(--m50); }
  .hint.bad { color: var(--danger); }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; margin-top: 8px; }
  .still { margin-right: auto; align-self: center; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
