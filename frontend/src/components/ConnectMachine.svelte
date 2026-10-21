<script lang="ts">
  // Add another computer on this network: its address, then its host key to confirm, then a login that only reads what it is. Nothing is installed here.
  import { untrack } from 'svelte'
  import AddRemote from './AddRemote.svelte'
  import Dialog from './Dialog.svelte'
  import CheckResult from './connect/CheckResult.svelte'
  import SecretField from './SecretField.svelte'
  import { ApiError, parentKey, remoteProbe, remoteVerify } from '../lib/api.ts'
  import { emptyConnectForm, groupedFingerprint, keyCommand, loginProblem, passwordAccepted, probeBody, userWarning, verifyBody, whereProblem } from '../lib/remote.ts'
  import type { ConnectForm, ProbeResult, VerifyResult } from '../lib/types.ts'

  type Step = 'where' | 'confirm' | 'result' | 'add'

  let { open, host = '', onClose, onInstalled }: { open: boolean; host?: string; onClose: () => void; onInstalled: () => void } = $props()
  let step: Step = $state('where')
  let form: ConnectForm = $state(emptyConnectForm())
  let probe = $state<ProbeResult | null>(null)
  let result: VerifyResult | null = $state(null)
  let publicKey = $state('')
  let busy = $state(false)
  let failure = $state('')
  const whereWrong = $derived(form.host ? whereProblem(form) : null)
  const loginWrong = $derived(loginProblem(form))
  const userWrong = $derived(userWarning(form.user))
  const STEPS: [Step, string][] = [['where', 'Computer'], ['confirm', 'Confirm'], ['result', 'Check'], ['add', 'Add']]
  const stepIndex = $derived(STEPS.findIndex(([id]) => id === step))

  $effect(() => {
    if (!open) return
    // Only opening the dialog starts it over: what is typed afterwards must not make this run again.
    untrack(() => {
      form = emptyConnectForm(host)
      step = 'where'
      probe = null
      result = null
      failure = ''
      busy = false
    })
  })

  /** Runs one step against the control panel, showing its refusal in plain words. */
  async function attempt(work: () => Promise<void>) {
    busy = true
    failure = ''
    try {
      await work()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      busy = false
    }
  }

  const look = (event: SubmitEvent) => {
    event.preventDefault()
    if (!whereWrong && form.host) attempt(async () => {
      const found = await remoteProbe(probeBody(form))
      probe = found
      step = 'confirm'
      // A computer that takes only keys gets the key steps at once: a password box would be a dead end.
      if (!passwordAccepted(found.login_methods)) await chooseKey(true)
    })
  }

  async function chooseKey(useKey: boolean) {
    form.useKey = useKey
    failure = ''
    copied = false
    if (!useKey || publicKey) return
    try { publicKey = await parentKey() } catch { failure = 'Could not read MetaService\'s key.' }
  }

  const login = (event: SubmitEvent) => {
    event.preventDefault()
    if (loginWrong || !probe) return
    const fingerprint = probe.fingerprint
    attempt(async () => {
      try {
        result = await remoteVerify(verifyBody(form, fingerprint))
        step = 'result'
      } finally {
        form.password = ''
      }
    })
  }

  const refused = $derived(/refused/i.test(failure))
  const passwordOk = $derived(passwordAccepted(probe?.login_methods))
  const pasteLine = $derived(keyCommand(publicKey))
  let copied = $state(false)

  async function copyKey() {
    try {
      await navigator.clipboard.writeText(pasteLine ?? publicKey)
      copied = true
    } catch {
      failure = 'Could not copy. Select the key and copy it by hand.'
    }
  }

  const again = () => { step = 'where'; probe = null; result = null; failure = '' }
</script>

<Dialog {open} title="Add a machine" {onClose}>
  <ol class="steps" aria-label="Steps">
    {#each STEPS as [id, label], index (id)}
      <li class:on={step === id} class:past={index < stepIndex} aria-current={step === id ? 'step' : undefined}><b>{index < stepIndex ? '✓' : index + 1}</b> <span class="t">{label}</span></li>
    {/each}
  </ol>

  {#if step === 'where'}
    <form onsubmit={look} novalidate>
      <p class="muted">Another computer on this network. This only looks: nothing is installed or changed on it.</p>
      <label for="connect-host">Address or name</label>
      <input id="connect-host" bind:value={form.host} autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="192.168.100.40" aria-invalid={whereWrong ? 'true' : 'false'} />
      <label for="connect-port">SSH port</label>
      <input id="connect-port" bind:value={form.port} inputmode="numeric" autocomplete="off" />
      <p class="hint {whereWrong ? 'bad' : 'muted'}">{whereWrong ?? 'It needs SSH on (Remote Login on a Mac). Only addresses on this network work.'}</p>
      {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
      <div class="row">
        <button class="btn line" type="button" onclick={onClose}>Cancel</button>
        <button class="btn green" type="submit" disabled={busy || !form.host || whereWrong !== null}>{busy ? 'Looking…' : 'Look at it'}</button>
      </div>
    </form>
  {:else if step === 'confirm' && probe}
    <form onsubmit={login} novalidate>
      <div class="found">
        <svg class="ico" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="12" rx="2" /><path d="M8 20h8M12 16v4" /></svg>
        <div>
          <strong>Found a computer at {probe.address}</strong>
          <p class="muted">{probe.host !== probe.address ? `${probe.host} · ` : ''}{probe.trusted ? 'You have connected to it before.' : 'This is the first time MetaService sees it.'}</p>
        </div>
      </div>
      <details class="why">
        <summary>Is it the right computer? (optional check)</summary>
        <p class="muted">Every computer has an ID code of its own, like a fingerprint. If you want to be sure this is yours and not another computer pretending, run this on it and compare:</p>
        <code class="key mono">ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub</code>
        <p class="print mono" aria-label="ID code of the computer (host key fingerprint)">{groupedFingerprint(probe.fingerprint)}</p>
      </details>

      <h3 class="sub">Log in to it</h3>
      <p class="muted">{form.useKey ? 'MetaService only looks at the computer; nothing is installed yet.' : 'Use the name and password you use to sign in on that computer. MetaService only looks; the password is used once and not kept.'}</p>
      <label for="connect-user">User name</label>
      <input id="connect-user" bind:value={form.user} autocomplete="off" autocapitalize="off" spellcheck="false" aria-invalid={userWrong !== null} aria-describedby={userWrong ? 'connect-user-warning' : undefined} />
      {#if userWrong}<p class="bad hint" id="connect-user-warning" role="alert">{userWrong}</p>{/if}
      {#if form.useKey}
        <ol class="how" aria-label="Steps to let MetaService in">
          <li><b>1</b><div>Open <strong>Terminal</strong> on that computer, signed in as <span class="mono">{form.user || 'that user'}</span>.<p class="muted">On a Mac: press ⌘ Space, type Terminal, press Enter.</p></div></li>
          <li>
            <b>2</b>
            <div>
              Paste this line there and press Enter.
              <code class="key mono" aria-label="Command that lets MetaService in">{pasteLine ?? (publicKey || '…')}</code>
              <button class="btn green sm" type="button" onclick={copyKey} disabled={!publicKey}>{copied ? 'Copied ✓' : 'Copy the line'}</button>
            </div>
          </li>
          <li><b>3</b><div>Come back here and press <strong>Log in and check</strong>.</div></li>
        </ol>
        {#if passwordOk}
          <button class="link" type="button" onclick={() => chooseKey(false)}>Use a password instead</button>
        {:else}
          <p class="muted keyhelp">This computer only accepts keys, so there is no password to type.</p>
        {/if}
      {:else}
        <SecretField label="Password" name="password" bind:value={form.password} />
        <button class="link" type="button" onclick={() => chooseKey(true)}>No password for it? Use a key instead</button>
      {/if}
      {#if failure}
        <p class="bad" role="alert">{failure}</p>
        {#if refused && !form.useKey}<p class="muted">Some computers do not accept passwords over the network. Then a key works: <button class="link" type="button" onclick={() => chooseKey(true)}>use a key instead</button>.</p>{/if}
      {/if}
      <div class="row">
        <button class="btn line" type="button" onclick={again}>Back</button>
        <button class="btn green" type="submit" disabled={busy || loginWrong !== null}>{busy ? 'Logging in…' : 'Log in and check'}</button>
      </div>
    </form>
  {:else if step === 'result' && result}
    <CheckResult {result} {form} onChecked={(fresh) => (result = fresh)} onAgain={again} onAdd={() => (step = 'add')} />
  {:else if step === 'add' && result}
    <AddRemote {form} {result} onBack={() => (step = 'result')} {onClose} {onInstalled} />
  {/if}
</Dialog>

<style>
  .steps { list-style: none; display: flex; gap: 18px; margin: 0 0 14px; padding: 0 0 10px; border-bottom: 1px solid var(--line); font-family: var(--mono); font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--m40); }
  .steps li.on { color: var(--text); font-weight: 700; }
  .steps li.past { color: var(--ok); }
  @media (max-width: 520px) { .steps { gap: 10px; } .steps li:not(.on) .t { display: none; } }
  .steps b { display: inline-block; min-width: 18px; text-align: center; border: 1px solid currentColor; border-radius: 50%; }
  label { display: block; margin-top: 14px; font-family: var(--mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  input:not([type='radio']) { display: block; width: 100%; margin-top: 6px; padding: 9px 10px; border: 1px solid var(--line); background: var(--surface); font-family: var(--mono); font-size: 14px; }
  input:focus { outline: 2px solid var(--accent-mark); outline-offset: -1px; }
  .found { display: flex; gap: 12px; align-items: center; padding: 12px 14px; border: 1px solid var(--line); background: var(--surface-2); }
  .found p { margin: 2px 0 0; font-size: 13px; }
  .ico { flex: none; color: var(--accent-mark); }
  .why { margin-top: 12px; font-size: 13px; }
  .why summary { cursor: pointer; color: var(--m50); }
  .how { list-style: none; margin: 12px 0 0; padding: 0; display: grid; gap: 14px; }
  .how li { display: grid; grid-template-columns: 24px 1fr; gap: 10px; align-items: start; }
  .how b { display: inline-block; width: 22px; height: 22px; line-height: 20px; text-align: center; border: 1px solid var(--accent-mark); border-radius: 50%; font-size: 12px; }
  .how p { margin: 2px 0 0; font-size: 13px; }
  .how .btn { margin-top: 8px; }
  .link { background: none; border: 0; padding: 0; margin-top: 10px; color: var(--m50); font-size: 13px; text-decoration: underline; cursor: pointer; }
  .print { padding: 12px 14px; background: var(--surface-2); border: 1px solid var(--line); font-size: 15px; letter-spacing: 0.04em; overflow-wrap: anywhere; }
  .key { display: block; padding: 10px; border: 1px solid var(--line); background: var(--surface); overflow-wrap: anywhere; user-select: all; font-size: 12px; }
  .sub { margin: 16px 0 6px; font-size: 13px; }
  .row { display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  .hint { font-size: 12px; margin-top: 6px; }
  .bad { color: var(--danger-bright); }
</style>
