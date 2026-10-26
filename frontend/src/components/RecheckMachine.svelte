<script lang="ts">
  // Check again: the same check as Add a machine, for a computer that is already added. Its address, SSH port and user come from the record the parent saved,
  // so only the login password (or MetaService's key) is needed. The parent checks that machine's own record, writes nothing, and this never adds a second machine:
  // the rows, the crosses and the "Install it for me" offers are the same components as the Add a machine check.
  import { untrack } from 'svelte'
  import CheckResult from './connect/CheckResult.svelte'
  import Dialog from './Dialog.svelte'
  import SecretField from './SecretField.svelte'
  import { remoteVerify } from '../lib/api.ts'
  import { ActionState } from '../lib/action.svelte.ts'
  import { actionLabel, retryLine } from '../lib/action.ts'
  import { emptyConnectForm, fixPasswordLabel, loginProblem, verifyBody } from '../lib/remote.ts'
  import { recheckForm, recheckProblem } from '../lib/recheck.ts'
  import { LONG_REQUEST_TIMEOUT_MS } from '../lib/timeouts.ts'
  import type { ConnectForm, Machine, RemoteMachineInfo, VerifyResult } from '../lib/types.ts'

  interface Props {
    open: boolean
    machine: Machine | null
    /** The machine's record, as Add a machine saved it; null for a machine that was not added over SSH. */
    remote: RemoteMachineInfo | null
    onClose: () => void
    /** Something on the parent may have changed (a check ran, a fix was installed): read the machines again. */
    onChecked: () => void
  }

  let { open, machine, remote, onClose, onChecked }: Props = $props()
  let form = $state(recheckFormOrEmpty())
  let result: VerifyResult | null = $state(null)
  const verify = new ActionState({ timeoutMs: LONG_REQUEST_TIMEOUT_MS })
  const busy = $derived(verify.busy)
  const cannot = $derived(machine ? recheckProblem(remote) : 'This machine is no longer in the list. Close this and open it from Machines again.')
  const loginWrong = $derived(loginProblem(form))
  const title = $derived(machine ? `Check ${machine.name} again` : 'Check this machine again')
  const checkLabel = $derived(actionLabel(verify.view, 'Log in and check', 'Checking…'))
  const retry = $derived(retryLine(verify.view))

  function recheckFormOrEmpty(): ConnectForm {
    return remote ? recheckForm(remote) : emptyConnectForm()
  }

  // Only opening the dialog starts it over: a machine read again while it is open must not wipe what is typed.
  $effect(() => {
    if (!open) return
    untrack(() => {
      form = recheckFormOrEmpty()
      result = null
      verify.reset()
    })
  })

  const check = (event: SubmitEvent) => {
    event.preventDefault()
    if (loginWrong || cannot || !machine) return
    void verify.run(async () => {
      try {
        result = await remoteVerify(verifyBody(form))
      } finally {
        form.password = ''
      }
      onChecked()
    })
  }

  /** Back to the login, with the password empty: the parent never keeps it. */
  function again() {
    result = null
    verify.reset()
    form = { ...form, password: '' }
  }

  function useKey() {
    form = { ...form, useKey: true, password: '' }
    verify.reset()
  }
</script>

<Dialog {open} {title} {onClose} closeButton locked={busy}>
  {#if cannot}
    <p class="muted">{cannot}</p>
    <div class="row"><button class="btn green" type="button" onclick={onClose}>Close</button></div>
  {:else if result}
    <CheckResult {result} {form} added onChecked={(fresh) => { result = fresh; onChecked() }} onAgain={again} {onClose} />
  {:else}
    <form onsubmit={check} novalidate>
      <p class="muted">This only looks at the computer. It is already added: nothing is installed unless you press <strong>Install it for me</strong>, and nothing is added a second time.</p>
      <dl class="where">
        <div><dt>Address</dt><dd class="mono">{form.host}</dd></div>
        <div><dt>SSH port</dt><dd class="mono">{form.port}</dd></div>
        <div><dt>User</dt><dd class="mono">{form.user}</dd></div>
      </dl>
      <h3 class="sub">Log in to it</h3>
      {#if form.useKey}
        <p class="muted">MetaService logs in with its own key, which is already on this computer. Nothing is typed.</p>
        <button class="link" type="button" onclick={() => (form = { ...form, useKey: false })}>Use a password instead</button>
      {:else}
        <SecretField label={fixPasswordLabel(form)} name="recheck-password" bind:value={form.password} />
        <p class="hint">{loginWrong ?? 'Typed once and not kept. With Install it for me the same password is used for the install, then forgotten.'}</p>
        {#if remote?.has_key}<button class="link" type="button" onclick={useKey}>No password for it? Use MetaService's key instead</button>{/if}
      {/if}
      {#if verify.message}<p class="bad" role="alert">{verify.message}</p>{/if}
      {#if retry}<p class="hint">{retry}</p>{/if}
      <div class="row">
        <button class="btn line" type="button" onclick={onClose}>Cancel</button>
        <button class="btn green" type="submit" disabled={busy || verify.cooling || loginWrong !== null} aria-busy={busy}>{checkLabel}</button>
      </div>
    </form>
  {/if}
</Dialog>

<style>
  .where { display: grid; gap: 6px; margin: 0; padding: 12px 14px; border: 1px solid var(--line); background: var(--surface-2); }
  .where div { display: grid; grid-template-columns: 96px minmax(0, 1fr); gap: 10px; align-items: baseline; }
  dt { font-family: var(--mono); font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--m50); }
  dd { margin: 0; overflow-wrap: anywhere; }
  .sub { margin: 4px 0 0; font-size: 13px; }
  .link { justify-self: start; background: none; border: 0; padding: 0; color: var(--m50); font-size: 13px; text-decoration: underline; cursor: pointer; }
  .row { display: flex; justify-content: flex-end; gap: 10px; }
  .hint { font-size: 12px; color: var(--m50); }
  .bad { color: var(--danger-bright); }
  @media (max-width: 520px) { .where div { grid-template-columns: 1fr; gap: 2px; } }
</style>
