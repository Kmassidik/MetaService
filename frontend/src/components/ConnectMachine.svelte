<script lang="ts">
  // Connect another computer on this network: its address, then its host key to confirm, then a login that only reads what it is. Nothing is installed here.
  import { untrack } from 'svelte'
  import AddRemote from './AddRemote.svelte'
  import Dialog from './Dialog.svelte'
  import Requirements from './Requirements.svelte'
  import SecretField from './SecretField.svelte'
  import { ApiError, parentKey, remoteProbe, remoteVerify } from '../lib/api.ts'
  import { emptyConnectForm, groupedFingerprint, isolationText, loginProblem, probeBody, verifyBody, whereProblem } from '../lib/remote.ts'
  import { formatGb, formatMb } from '../lib/format.ts'
  import type { ConnectForm, ProbeResult, VerifyResult } from '../lib/types.ts'

  type Step = 'where' | 'confirm' | 'result' | 'add'

  let { open, host = '', onClose, onInstalled }: { open: boolean; host?: string; onClose: () => void; onInstalled: () => void } = $props()
  let step: Step = $state('where')
  let form: ConnectForm = $state(emptyConnectForm())
  let probe: ProbeResult | null = $state(null)
  let result: VerifyResult | null = $state(null)
  let publicKey = $state('')
  let busy = $state(false)
  let failure = $state('')
  const whereWrong = $derived(form.host ? whereProblem(form) : null)
  const loginWrong = $derived(loginProblem(form))
  const STEPS: [Step, string][] = [['where', 'Computer'], ['confirm', 'Confirm'], ['result', 'Check'], ['add', 'Add']]

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
    if (!whereWrong && form.host) attempt(async () => { probe = await remoteProbe(probeBody(form)); step = 'confirm' })
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
  let copied = $state(false)

  async function copyKey() {
    try {
      await navigator.clipboard.writeText(publicKey)
      copied = true
    } catch {
      failure = 'Could not copy. Select the key and copy it by hand.'
    }
  }

  const again = () => { step = 'where'; probe = null; result = null; failure = '' }
</script>

<Dialog {open} title="Connect a computer" {onClose}>
  <ol class="steps" aria-label="Steps">
    {#each STEPS as [id, label], index (id)}<li class:on={step === id} aria-current={step === id ? 'step' : undefined}><b>{index + 1}</b> {label}</li>{/each}
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
      <input id="connect-user" bind:value={form.user} autocomplete="off" autocapitalize="off" spellcheck="false" />
      {#if form.useKey}
        <p class="muted keyhelp">Instead of a password, give that computer MetaService's key. On that computer, add this line to the file <span class="mono">~/.ssh/authorized_keys</span> of that user:</p>
        <code class="key mono" aria-label="MetaService's public key">{publicKey || '…'}</code>
        <div class="keyactions">
          <button class="btn line sm" type="button" onclick={copyKey} disabled={!publicKey}>{copied ? 'Copied' : 'Copy the key'}</button>
          <button class="link" type="button" onclick={() => chooseKey(false)}>Use a password instead</button>
        </div>
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
    <p><strong>{result.system || result.host}</strong></p>
    <p class="muted">{result.facts.cpu_cores ?? '–'} cores · {formatMb(result.facts.ram_mb)} memory · {formatGb(result.facts.disk_free_gb)} free · logged in as {result.facts.user}</p>
    <Requirements items={result.requirements} label="What that computer has" />
    <h3 class="sub">Where MetaService would go</h3>
    <ul class="levels">{#each result.isolation as level (level)}<li>{isolationText(level)}</li>{/each}</ul>
    {#if result.can_add}
      <p class="good" role="status">Looks good. MetaService can be installed on this computer.</p>
    {:else}
      <p class="bad" role="alert">It cannot be added yet: fix the ✗ above first.</p>
    {/if}
    <div class="row">
      <button class="btn line" type="button" onclick={again}>Check another</button>
      <button class="btn green" type="button" disabled={!result.can_add} onclick={() => (step = 'add')}>Add machine</button>
    </div>
  {:else if step === 'add' && result}
    <AddRemote {form} {result} onBack={() => (step = 'result')} {onClose} {onInstalled} />
  {/if}
</Dialog>

<style>
  .steps { list-style: none; display: flex; gap: 18px; margin: 0 0 14px; padding: 0 0 10px; border-bottom: 1px solid var(--gray); font-family: var(--mono); font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--m40); }
  .steps li.on { color: var(--black); }
  .steps b { display: inline-block; min-width: 18px; text-align: center; border: 1px solid currentColor; border-radius: 50%; }
  label { display: block; margin-top: 14px; font-family: var(--mono); font-size: 11px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--m50); }
  input:not([type='radio']) { display: block; width: 100%; margin-top: 6px; padding: 9px 10px; border: 1px solid var(--gray); background: var(--white); font-family: var(--mono); font-size: 14px; }
  input:focus { outline: 2px solid var(--green); outline-offset: -1px; }
  .found { display: flex; gap: 12px; align-items: center; padding: 12px 14px; border: 1px solid var(--gray); background: var(--gray2); }
  .found p { margin: 2px 0 0; font-size: 13px; }
  .ico { flex: none; color: var(--green); }
  .why { margin-top: 12px; font-size: 13px; }
  .why summary { cursor: pointer; color: var(--m50); }
  .keyactions { display: flex; align-items: center; gap: 14px; margin-top: 10px; }
  .link { background: none; border: 0; padding: 0; margin-top: 10px; color: var(--m50); font-size: 13px; text-decoration: underline; cursor: pointer; }
  .keyactions .link { margin-top: 0; }
  .print { padding: 12px 14px; background: var(--gray2); border: 1px solid var(--gray); font-size: 15px; letter-spacing: 0.04em; overflow-wrap: anywhere; }
  .key { display: block; padding: 10px; border: 1px solid var(--gray); background: var(--bg); overflow-wrap: anywhere; user-select: all; font-size: 12px; }
  .sub { margin: 16px 0 6px; font-size: 13px; }
  .levels { margin: 0; padding-left: 18px; display: grid; gap: 4px; font-size: 13px; }
  .row { display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  .hint { font-size: 12px; margin-top: 6px; }
  .bad { color: #d92d20; }
  .good { color: var(--run); }
</style>
