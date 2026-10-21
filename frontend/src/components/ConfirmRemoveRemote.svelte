<script lang="ts">
  // Removing a machine that was installed over SSH: log in once more to take MetaService off that computer (the box and the tunnel key), or only forget it here.
  import { untrack } from 'svelte'
  import Dialog from './Dialog.svelte'
  import SecretField from './SecretField.svelte'
  import { emptyConnectForm, removeBody } from '../lib/remote.ts'
  import type { ConnectForm, Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { machine, info, busy, failure, onCancel, onConfirm }: { machine: Machine | null; info: RemoteMachineInfo | null; busy: boolean; failure: string; onCancel: () => void; onConfirm: (body: Record<string, unknown>) => void } = $props()
  let form: ConnectForm = $state(emptyConnectForm())
  let forgetOnly = $state(false)
  const ready = $derived(!busy && (forgetOnly || form.useKey || form.password !== ''))

  $effect(() => {
    if (!machine) return
    untrack(() => {
      form = emptyConnectForm()
      forgetOnly = false
    })
  })

  const confirm = (event: SubmitEvent) => {
    event.preventDefault()
    if (!ready) return
    const body = removeBody(form, forgetOnly)
    form.password = ''
    onConfirm(body)
  }
</script>

<Dialog open={machine !== null && info !== null} title="Remove this machine?" onClose={onCancel}>
  {#if machine && info}
    <form onsubmit={confirm} novalidate>
      <p><strong>{machine.name}</strong> was installed on <span class="mono">{info.ssh_user}@{info.host}</span>. Removing it takes MetaService away from that computer and forgets the machine here.</p>
      <fieldset>
        <legend>How</legend>
        <label class="check"><input type="radio" name="how" checked={!forgetOnly} onchange={() => (forgetOnly = false)} /> Log in and take it away (stops the program, removes {info.box}{info.has_key ? ' and the tunnel key line' : ''})</label>
        <label class="check"><input type="radio" name="how" checked={forgetOnly} onchange={() => (forgetOnly = true)} /> Only forget it here (the computer is gone; its box stays as it is)</label>
      </fieldset>
      {#if !forgetOnly}
        <label class="check"><input type="checkbox" bind:checked={form.useKey} /> Use the parent's key instead of a password</label>
        {#if !form.useKey}<SecretField label="Password (used once)" name="password" bind:value={form.password} />{/if}
      {/if}
      {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
      <div class="row">
        <button class="btn line" type="button" onclick={onCancel}>Keep it</button>
        <button class="btn danger" type="submit" disabled={!ready}>{busy ? 'Removing…' : 'Remove machine'}</button>
      </div>
    </form>
  {/if}
</Dialog>

<style>
  fieldset { border: 0; border-top: 1px solid var(--line); margin: 16px 0 0; padding: 0; }
  legend { padding: 0 8px 0 0; margin-top: -9px; background: var(--surface); font-family: var(--mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--m40); }
  .check { display: flex; gap: 8px; align-items: center; font-size: 14px; margin-top: 10px; }
  .check input { margin: 0; }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; margin-top: 16px; }
  .bad { color: var(--danger); }
</style>
