<script lang="ts">
  // Sign in and first run on one two-column page: the pitch on the left, the form on the right.
  import { ApiError, login, setupAdmin } from '../lib/api.ts'
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
  <div class="pitch">
    <div class="brand"><span class="sq"></span>MetaService</div>
    <div>
      <h1>One panel for <span class="hl">every machine</span>.</h1>
      <p class="lede">Add your machines, create VMs and containers on them, open the chat on each one and see their screens. Macs and Linux, one place.</p>
    </div>
    <svg class="diagram" viewBox="0 0 520 150" role="img" aria-label="One parent connected to four machines">
      <g stroke="rgba(250,250,250,.35)" stroke-width="1.5" fill="none">
        <path d="M260 40 L70 110" /><path d="M260 40 L195 110" /><path d="M260 40 L325 110" /><path d="M260 40 L450 110" />
      </g>
      <g stroke="#00f56d" stroke-width="1.5" fill="none" stroke-dasharray="3 5"><path d="M260 40 L195 110" /><path d="M260 40 L325 110" /></g>
      <rect x="226" y="14" width="68" height="40" fill="#111" stroke="#00f56d" stroke-width="1.5" />
      <text x="260" y="39" text-anchor="middle" fill="#fafafa" font-family="monospace" font-size="12" font-weight="700">PARENT</text>
      {#each [70, 195, 325, 450] as x, index (x)}
        <rect x={x - 34} y="96" width="68" height="36" fill="#111" stroke="rgba(250,250,250,.55)" stroke-width="1.5" />
        <rect x={x - 26} y="104" width="6" height="6" fill={index < 3 ? '#00f56d' : 'rgba(250,250,250,.4)'} />
        <text x={x + 4} y="119" text-anchor="middle" fill="rgba(250,250,250,.8)" font-family="monospace" font-size="11">machine</text>
      {/each}
    </svg>
    <div class="facts">
      <span><b>Private</b>Over SSH tunnels</span>
      <span><b>Isolated</b>Only adds, never edits</span>
      <span><b>Yours</b>Runs on your network</span>
    </div>
  </div>
  <div class="form-wrap">
    <form onsubmit={submit}>
      <div class="mobilebrand"><span class="sq"></span>MetaService</div>
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
</div>

<style>
  .small { font-size: 11px; font-family: var(--mono); }
  form .btn { width: 100%; padding: 12px 15px; }
  .note { font-family: var(--mono); font-size: 11px; color: var(--m50); margin: -4px 0 12px; }
  .hintline { font-family: var(--mono); font-size: 12px; color: var(--m50); min-height: 18px; margin-bottom: 14px; }
  .hintline.ok { color: var(--run); }
  .hintline.no { color: #d92d20; }
</style>
