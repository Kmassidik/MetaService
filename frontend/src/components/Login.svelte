<script>
  // Sign in and first run on one two-column page: the pitch on the left, the form on the right.
  import { ApiError, login, setupAdmin } from '../lib/api.js'
  import SecretField from './SecretField.svelte'

  let { configured, onDone } = $props()
  let username = $state('')
  let password = $state('')
  let confirm = $state('')
  let setupToken = $state('')
  let busy = $state(false)
  let failure = $state('')

  const MIN_LENGTH = 8
  /** Live hints, as in the MAAS panel: length first, then whether the two passwords match. */
  const hint = $derived.by(() => {
    if (configured || (!password && !confirm)) return { text: '', tone: '' }
    if (password.length < MIN_LENGTH) return { text: `Use at least ${MIN_LENGTH} characters (${password.length}/${MIN_LENGTH}).`, tone: 'no' }
    if (confirm && password !== confirm) return { text: "Passwords don't match yet.", tone: 'no' }
    if (password === confirm) return { text: 'Passwords match.', tone: 'ok' }
    return { text: '', tone: '' }
  })
  const ready = $derived(configured ? Boolean(username && password) : Boolean(username && setupToken && password.length >= MIN_LENGTH && password === confirm))

  async function submit(event) {
    event.preventDefault()
    busy = true
    failure = ''
    try {
      await (configured ? login(username, password) : setupAdmin(username, password, confirm, setupToken))
      password = ''
      confirm = ''
      setupToken = ''
      await onDone()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      busy = false
    }
  }
</script>

<div class="login">
  <div class="pitch">
    <div class="brand"><span class="sq"></span>MetaService</div>
    <div>
      <h1>One panel for <span class="hl">every machine</span>.</h1>
      <p class="lede">Register machines, create VMs and containers on them, and open the chat on each one. Macs and Linux boxes, one place.</p>
    </div>
    <span class="lede small">Root · Agents · VMs</span>
  </div>
  <div class="form-wrap">
    <form onsubmit={submit}>
      <span class="flabel">{configured ? 'Sign in to manage your machines' : 'First run — create your admin login'}</span>
      {#if failure}<div class="err" role="alert">{failure}</div>{/if}
      <label class="field"><span>Username</span><input name="username" autocomplete="username" required bind:value={username} /></label>
      <SecretField label="Password" name="password" autocomplete={configured ? 'current-password' : 'new-password'} placeholder={configured ? '' : 'at least 8 characters'} bind:value={password} />
      {#if !configured}
        <SecretField label="Confirm password" name="confirm" autocomplete="new-password" bind:value={confirm} />
        <SecretField label="Setup token" name="setup_token" placeholder="provided by the operator" bind:value={setupToken} />
        <p class="note">A one-time operator token is required to claim this panel. It is ROOT_SETUP_TOKEN in the control plane's .env file.</p>
        <div class="hintline {hint.tone}" role="status">{hint.text}</div>
      {/if}
      <button class="btn green" type="submit" disabled={busy || !ready}>{busy ? 'Please wait…' : configured ? 'Sign in' : 'Create admin & sign in'}</button>
    </form>
  </div>
</div>

<style>
  .small { font-size: 11px; font-family: var(--mono); }
  h1 { max-width: 30ch; }
  form .btn { width: 100%; padding: 12px 15px; }
  .note { font-family: var(--mono); font-size: 11px; color: var(--m50); margin: -4px 0 12px; }
  .hintline { font-family: var(--mono); font-size: 12px; color: var(--m50); min-height: 18px; margin-bottom: 14px; }
  .hintline.ok { color: var(--run); }
  .hintline.no { color: #d92d20; }
</style>
