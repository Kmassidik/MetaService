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
    if (!useKey || publicKey) return
    try { publicKey = await parentKey() } catch { failure = 'Could not read the parent\'s key.' }
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
      <p>Is this the computer you mean? Compare this fingerprint with the one on that computer (<span class="mono">ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub</span>).</p>
      <p class="print mono" aria-label="Host key fingerprint">{groupedFingerprint(probe.fingerprint)}</p>
      <p class="muted">{probe.host} · {probe.address} · {probe.key_type}{probe.trusted ? ' · trusted before' : ''}</p>

      <label for="connect-user">User on that computer</label>
      <input id="connect-user" bind:value={form.user} autocomplete="off" autocapitalize="off" spellcheck="false" />
      <fieldset class="how">
        <legend>How to log in</legend>
        <label class="check"><input type="radio" name="how" checked={!form.useKey} onchange={() => chooseKey(false)} /> Password (used once, never kept)</label>
        <label class="check"><input type="radio" name="how" checked={form.useKey} onchange={() => chooseKey(true)} /> The parent's key (add it to that computer first)</label>
      </fieldset>
      {#if form.useKey}
        <p class="muted">Put this line in <span class="mono">~/.ssh/authorized_keys</span> of that user:</p>
        <code class="key mono" aria-label="The parent's public key">{publicKey || '…'}</code>
      {:else}
        <SecretField label="Password" name="password" bind:value={form.password} />
      {/if}
      {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
      <div class="row">
        <button class="btn line" type="button" onclick={again}>Back</button>
        <button class="btn green" type="submit" disabled={busy || loginWrong !== null}>{busy ? 'Logging in…' : 'Yes, log in and check'}</button>
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
  fieldset.how { border: 0; border-top: 1px solid var(--gray); margin: 16px 0 0; padding: 0; }
  legend { padding: 0 8px 0 0; margin-top: -9px; background: var(--white); font-family: var(--mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--m40); }
  .check { display: flex; gap: 8px; align-items: center; text-transform: none; letter-spacing: 0; font-family: var(--sans); font-size: 14px; color: var(--black); margin-top: 10px; }
  .check input { width: auto; margin: 0; }
  .print { padding: 12px 14px; background: var(--gray2); border: 1px solid var(--gray); font-size: 15px; letter-spacing: 0.04em; overflow-wrap: anywhere; }
  .key { display: block; padding: 10px; border: 1px solid var(--gray); background: var(--bg); overflow-wrap: anywhere; user-select: all; font-size: 12px; }
  .sub { margin: 16px 0 6px; font-size: 13px; }
  .levels { margin: 0; padding-left: 18px; display: grid; gap: 4px; font-size: 13px; }
  .row { display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  .hint { font-size: 12px; margin-top: 6px; }
  .bad { color: #d92d20; }
  .good { color: var(--run); }
</style>
