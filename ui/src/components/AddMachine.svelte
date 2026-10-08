<script>
  import Dialog from './Dialog.svelte'
  import { inviteMachine, ApiError } from '../lib/api.js'
  import { nameProblem } from '../lib/format.js'

  let { open, onClose, onCreated } = $props()
  let name = $state('')
  let busy = $state(false)
  let failure = $state('')
  let invite = $state(null)
  let copied = $state(false)
  const problem = $derived(name ? nameProblem(name) : null)

  $effect(() => {
    if (open) reset()
  })

  function reset() {
    name = ''
    busy = false
    failure = ''
    invite = null
    copied = false
  }

  async function submit(event) {
    event.preventDefault()
    const found = nameProblem(name)
    if (found) {
      failure = found
      return
    }
    busy = true
    failure = ''
    try {
      invite = await inviteMachine(name)
      onCreated()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      busy = false
    }
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(invite.enrollment_token)
      copied = true
    } catch {
      copied = false
    }
  }
</script>

<Dialog {open} title={invite ? 'Enrollment token' : 'Add a machine'} {onClose}>
  {#if invite}
    <p>Use this token on <strong>{invite.name}</strong> when you install the Agent. It works once and expires at
      <span class="nums">{new Date(invite.expires_at).toLocaleTimeString()}</span>. It is not shown again.</p>
    <code class="token mono">{invite.enrollment_token}</code>
    <div class="row">
      <button class="btn" type="button" onclick={copy}>{copied ? 'Copied' : 'Copy token'}</button>
      <button class="btn primary" type="button" onclick={onClose}>Done</button>
    </div>
  {:else}
    <form onsubmit={submit} novalidate>
      <label for="machine-name">Machine name</label>
      <input id="machine-name" bind:value={name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" placeholder="dgx-spark" aria-invalid={problem ? 'true' : 'false'} />
      <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'Lowercase letters, numbers and dashes. This is how the machine appears here.'}</p>
      {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
      <div class="row">
        <button class="btn" type="button" onclick={onClose}>Cancel</button>
        <button class="btn primary" type="submit" disabled={busy || !name || !!problem}>{busy ? 'Creating…' : 'Create token'}</button>
      </div>
    </form>
  {/if}
</Dialog>

<style>
  form { display: grid; gap: 10px; }
  label { font-weight: 600; }
  input {
    min-height: 42px;
    padding: 0 12px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--bg);
  }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .hint { font-size: 13px; }
  .bad { color: var(--danger); }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
  .token {
    display: block;
    padding: 12px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--bg);
    overflow-wrap: anywhere;
    user-select: all;
  }
</style>
