<script>
  // The sign-in and first-run pages, copied from the MAAS panel (web/login.html, web/setup.html, web/style.css): one centered card.
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
  /** The same live hints as MAAS: length first, then whether the two passwords match. */
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

<div class="auth">
  <div class="auth-card">
    <span class="pill">Control plane</span>
    <div class="wordmark"><span class="sq"></span>MetaService operator</div>
    {#if configured}
      <p class="sub">Sign in to manage your <span class="mark">machines</span>.</p>
    {:else}
      <p class="sub">First run — create your <span class="mark">admin login</span>.</p>
    {/if}
    {#if failure}<div class="err" role="alert">{failure}</div>{/if}
    <form onsubmit={submit}>
      <label for="username">Username</label>
      <div class="inp"><input id="username" name="username" autocomplete="username" required bind:value={username} /></div>
      <SecretField label="Password" name="password" autocomplete={configured ? 'current-password' : 'new-password'} placeholder={configured ? '' : 'at least 8 characters'} bind:value={password} />
      {#if !configured}
        <SecretField label="Confirm password" name="confirm" autocomplete="new-password" bind:value={confirm} />
        <SecretField label="Setup token" name="setup_token" placeholder="provided by the operator" bind:value={setupToken} />
        <p class="hint">A one-time operator token is required to claim this panel.</p>
        <div class="hint {hint.tone}" role="status">{hint.text}</div>
      {/if}
      <button class="go" type="submit" disabled={busy || !ready}>{busy ? 'Please wait…' : configured ? 'Sign in' : 'Create admin & sign in'}</button>
    </form>
  </div>
</div>

<style>
  .auth { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
  .auth-card { width: 100%; max-width: 420px; border: 1px solid var(--gray); padding: 40px; }
  .pill { display: inline-block; background: var(--green); color: var(--black); font-family: var(--mono); font-size: 10px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; padding: 5px 10px; }
  .wordmark { display: flex; align-items: center; gap: 12px; font-family: var(--mono); font-size: 16px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; margin: 20px 0 4px; }
  .wordmark .sq { width: 12px; height: 12px; background: var(--green); border: 1px solid var(--black); box-shadow: 0 0 6px var(--green); }
  .sub { font-family: var(--mono); font-size: 13px; color: var(--m60); margin: 0 0 28px; line-height: 1.6; }
  .mark { background: var(--green); color: var(--black); padding: 0 0.1em; }
  :global(.auth-card label) { display: block; font-family: var(--mono); font-size: 11px; color: var(--m50); text-transform: uppercase; letter-spacing: 0.14em; margin: 20px 0 6px; }
  :global(.auth-card .inp) { position: relative; }
  :global(.auth-card input) { width: 100%; background: transparent; border: 0; border-bottom: 1px solid var(--gray); padding: 8px 34px 8px 0; font-family: var(--mono); font-size: 15px; color: var(--black); }
  :global(.auth-card input:hover) { border-bottom-color: var(--m50); }
  :global(.auth-card input:focus) { border-bottom-color: var(--black); outline: none; }
  :global(.auth-card input::placeholder) { color: var(--m40); }
  :global(.auth-card .eye) { position: absolute; right: 0; bottom: 6px; background: none; border: 0; color: var(--m40); padding: 2px; line-height: 0; }
  :global(.auth-card .eye:hover) { color: var(--black); }
  .go { width: 100%; margin-top: 28px; background: var(--green); color: var(--black); border: 1px solid var(--black); padding: 14px; font-family: var(--mono); font-weight: 700; text-transform: uppercase; letter-spacing: 0.16em; font-size: 13px; }
  .go:hover { background: var(--black); color: var(--green); }
  .go:disabled { opacity: 0.4; cursor: not-allowed; }
  .go:disabled:hover { background: var(--green); color: var(--black); }
  .hint { font-family: var(--mono); font-size: 12px; color: var(--m50); margin-top: 8px; min-height: 15px; }
  .hint.ok { color: #0a8f45; }
  .hint.no { color: #d92d20; }
  .err { border: 1px solid #f1b0b0; background: #fdeaea; color: #a3282c; font-family: var(--mono); font-size: 12px; padding: 10px 12px; margin-bottom: 16px; }
</style>
