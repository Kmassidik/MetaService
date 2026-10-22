<script lang="ts">
  // Sign in and first run on one centered column: the owl, the name, then the form card.
  import { ApiError, login, setupAdmin } from '../lib/api.ts'
  import Owl from './Owl.svelte'
  import SecretField from './SecretField.svelte'

  let { configured, minLength = 8, onDone }: { configured: boolean; minLength?: number; onDone: () => void | Promise<void> } = $props()
  let username = $state('')
  let password = $state('')
  let confirm = $state('')
  let setupToken = $state('')
  let busy = $state(false)
  let failure = $state('')

  /** Live hints, as in the MAAS panel: length first, then whether the two passwords match. */
  const hint = $derived.by(() => {
    if (configured || (!password && !confirm)) return { text: '', tone: '' }
    if (password.length < minLength) return { text: `Use at least ${minLength} characters (${password.length}/${minLength}).`, tone: 'no' }
    if (confirm && password !== confirm) return { text: "Passwords don't match yet.", tone: 'no' }
    if (password === confirm) return { text: 'Passwords match.', tone: 'ok' }
    return { text: '', tone: '' }
  })
  const ready = $derived(configured ? Boolean(username && password) : Boolean(username && setupToken && password.length >= minLength && password === confirm))

  async function submit(event: SubmitEvent) {
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
  <Owl name="hero" eager />
  <div class="brand">MetaService</div>
  <form onsubmit={submit}>
    <h2 class="formtitle">{configured ? 'Sign in' : 'Create your admin login'}</h2>
    <span class="flabel">{configured ? 'Sign in to manage your machines, VMs and chats.' : 'First run: claim this panel with the operator setup token.'}</span>
    {#if failure}<div class="err" role="alert">{failure}</div>{/if}
    <label class="field"><span>Username</span><input name="username" autocomplete="username" required bind:value={username} /></label>
    <SecretField label="Password" name="password" autocomplete={configured ? 'current-password' : 'new-password'} placeholder={configured ? '' : `at least ${minLength} characters`} bind:value={password} />
    {#if !configured}
      <SecretField label="Confirm password" name="confirm" autocomplete="new-password" bind:value={confirm} />
      <SecretField label="Setup token" name="setup_token" placeholder="provided by the operator" bind:value={setupToken} />
      <p class="note">A one-time operator token is required to claim this panel. It is ROOT_SETUP_TOKEN in the control plane's .env file.</p>
      <div class="hintline {hint.tone}" role="status">{hint.text}</div>
    {/if}
    <button class="btn green" type="submit" disabled={busy || !ready}>{busy ? 'Please wait…' : configured ? 'Sign in' : 'Create admin & sign in'}</button>
    <p class="formfoot">Operator access only</p>
  </form>
</div>

<style>
  .small { font-size: 11px; font-family: var(--mono); }
  form .btn { width: 100%; padding: 12px 15px; }
  .note { font-family: var(--mono); font-size: 11px; color: var(--m50); margin: -4px 0 12px; }
  .hintline { font-family: var(--mono); font-size: 12px; color: var(--m50); min-height: 18px; margin-bottom: 14px; }
  .hintline.ok { color: var(--ok); }
  .hintline.no { color: var(--danger-bright); }
</style>
