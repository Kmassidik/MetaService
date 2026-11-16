<script lang="ts">
  // Removing a machine in the shared red dialog. A machine that was installed over SSH adds one choice: log in once more to take MetaService off that computer
  // (the box and the tunnel key), or only forget it here.
  import { untrack } from 'svelte'
  import ConfirmDialog from './ConfirmDialog.svelte'
  import SecretField from './SecretField.svelte'
  import { removeMachineCopy, removeRemoteMachineCopy } from '../lib/confirmCopy.ts'
  import { cleanReady, isSharedMachine } from '../lib/leave.ts'
  import { emptyConnectForm, removeBody } from '../lib/remote.ts'
  import type { ConnectForm, Machine, RemoteMachineInfo } from '../lib/types.ts'

  interface Props {
    machine: Machine | null
    /** Set when the machine was installed over SSH. */
    info: RemoteMachineInfo | null
    /** Removes the machine; `body` is the SSH login choice, or null for a plain machine. For a machine that joined through Share a PC it is `{ shared: true, clean, sudo_password }`. Throws the refusal. */
    onconfirm: (machine: Machine, body: Record<string, unknown> | null) => Promise<unknown>
    onClose: () => void
  }

  let { machine, info, onconfirm, onClose }: Props = $props()
  let form: ConnectForm = $state(emptyConnectForm())
  let forgetOnly = $state(false)
  let clean = $state(true)
  let sudoPassword = $state('')
  const shared = $derived(machine !== null && info === null && isSharedMachine(machine))
  const copy = $derived(machine ? (info ? removeRemoteMachineCopy(machine, info) : removeMachineCopy(machine)) : removeMachineCopy({ name: '' }))
  const ready = $derived(shared ? cleanReady(clean, sudoPassword) : info === null || forgetOnly || form.useKey || form.password !== '')

  $effect(() => {
    if (!machine) return
    untrack(() => {
      form = emptyConnectForm()
      forgetOnly = false
      clean = true
      sudoPassword = ''
    })
  })

  /** The password is used once: it is taken out of the form as the request starts. */
  function confirm(): Promise<unknown> {
    if (!machine) return Promise.resolve()
    if (shared) {
      const body = { shared: true, clean, sudo_password: sudoPassword }
      sudoPassword = ''
      return onconfirm(machine, body)
    }
    const body = info ? removeBody(form, forgetOnly) : null
    form.password = ''
    return onconfirm(machine, body)
  }
</script>

<ConfirmDialog open={machine !== null} {...copy} {ready} onconfirm={confirm} {onClose}>
  {#if shared}
    <label class="check"><input type="checkbox" bind:checked={clean} /> Also clean the computer: stop its helper and WireGuard, remove its boot entries and delete its join folder (recommended)</label>
    {#if clean}
      <SecretField label={`Sudo password of ${machine?.name ?? 'that computer'}`} name="sudo-password" bind:value={sudoPassword} />
      <p class="hint">Typed once, sent to that computer's helper, used for this one clean-up and never saved. A wrong password changes nothing and the machine stays listed.</p>
    {/if}
  {/if}
  {#if info}
    <fieldset>
      <legend>How</legend>
      <label class="check"><input type="radio" name="how" checked={!forgetOnly} onchange={() => (forgetOnly = false)} /> Log in and take it away (stops the program, removes {info.box}{info.has_key ? ' and the tunnel key line' : ''})</label>
      <label class="check"><input type="radio" name="how" checked={forgetOnly} onchange={() => (forgetOnly = true)} /> Only forget it here (the computer is gone; its box stays as it is)</label>
    </fieldset>
    {#if !forgetOnly}
      <label class="check"><input type="checkbox" bind:checked={form.useKey} /> Use the parent's key instead of a password</label>
      {#if !form.useKey}<SecretField label="Password (used once)" name="password" bind:value={form.password} />{/if}
    {/if}
  {/if}
</ConfirmDialog>

<style>
  fieldset { border: 0; border-top: 1px solid var(--line); margin: 4px 0 0; padding: 0; }
  legend { padding: 0 8px 0 0; margin-top: -9px; background: var(--surface); font-family: var(--mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--m40); }
  .check { display: flex; gap: 8px; align-items: center; font-size: 14px; margin-top: 10px; }
  .check input { margin: 0; }
  .hint { margin: 4px 0 0; font-size: 12px; color: var(--m50); }
</style>
