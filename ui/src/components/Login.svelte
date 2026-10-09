<script>
  import { ApiError, login, setupAdmin } from '../lib/api.js'

  let { configured, onDone } = $props()
  let username = $state('')
  let password = $state('')
  let confirm = $state('')
  let busy = $state(false)
  let failure = $state('')

  async function submit(event) {
    event.preventDefault()
    busy = true
    failure = ''
    try {
      await (configured ? login(username, password) : setupAdmin(username, password, confirm))
      password = ''
      confirm = ''
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
      <label class="field"><span>Password{configured ? '' : ' (8 characters or more)'}</span>
        <input name="password" type="password" autocomplete={configured ? 'current-password' : 'new-password'} required bind:value={password} />
      </label>
      {#if !configured}
        <label class="field"><span>Confirm password</span><input name="confirm" type="password" autocomplete="new-password" required bind:value={confirm} /></label>
      {/if}
      <button class="btn green" type="submit" disabled={busy}>{busy ? 'Please wait…' : configured ? 'Sign in' : 'Create admin login'}</button>
    </form>
  </div>
</div>

<style>
  .small { font-size: 11px; font-family: var(--mono); }
  h1 { max-width: 30ch; }
  form .btn { width: 100%; padding: 12px 15px; }
</style>
