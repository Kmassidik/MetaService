<script>
  import { ApiError, login, setupAdmin } from '../lib/api.js'
  import SecretField from './SecretField.svelte'

  let { configured, onDone } = $props()
  let username = $state('')
  let password = $state('')
  let confirm = $state('')
  let setupToken = $state('')
  let busy = $state(false)
  let failure = $state('')
  const match = $derived(confirm === '' ? null : confirm === password)

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
      <span class="flabel">{configured ? 'Operator sign in' : 'First run: create the admin login'}</span>
      {#if failure}<div class="err" role="alert">{failure}</div>{/if}
      <label class="field"><span>Username</span><input name="username" autocomplete="username" required bind:value={username} /></label>
      <SecretField label="Password" name="password" autocomplete={configured ? 'current-password' : 'new-password'} hint={configured ? '' : '8 characters or more'} bind:value={password} />
      {#if !configured}
        <SecretField label="Confirm password" name="confirm" autocomplete="new-password" bind:value={confirm} />
        {#if match !== null}
          <p class="match" class:ok={match} role="status">{match ? '✓ The two passwords are the same' : '✗ The two passwords are different'}</p>
        {/if}
        <SecretField label="Setup token" name="setup_token" hint="It is ROOT_SETUP_TOKEN in the Root's env file. The Root writes one there on its first start if there is none." bind:value={setupToken} />
      {/if}
      <button class="btn green" type="submit" disabled={busy || (!configured && match === false)}>{busy ? 'Please wait…' : configured ? 'Sign in' : 'Create admin login'}</button>
    </form>
  </div>
</div>

<style>
  .small { font-size: 11px; font-family: var(--mono); }
  h1 { max-width: 30ch; }
  form .btn { width: 100%; padding: 12px 15px; }
  .match { margin: -6px 0 16px; font-family: var(--mono); font-size: 11px; color: var(--red, #c0392b); }
  .match.ok { color: var(--run); }
</style>
