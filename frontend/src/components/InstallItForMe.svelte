<script lang="ts">
  // "Install it for me", under a ✗ the parent can fix itself: a button, then a password field. The password goes to the parent in one request and is forgotten as soon as it is answered.
  import SecretField from './SecretField.svelte'
  import { ApiError, remoteFix } from '../lib/api.ts'
  import { fixBody, fixNeedsPassword, fixPasswordLabel, fixWhat } from '../lib/remote.ts'
  import type { ConnectForm, InstallOffer, VerifyResult } from '../lib/types.ts'

  let { offer, form, fingerprint, onChecked }: { offer: InstallOffer; form: ConnectForm; fingerprint: string; onChecked: (result: VerifyResult) => void } = $props()
  let open = $state(false)
  let password = $state('')
  let busy = $state(false)
  let failure = $state('')
  const needsPassword = $derived(fixNeedsPassword(form, offer))
  const ready = $derived(!busy && (!needsPassword || password !== ''))

  async function install(event: SubmitEvent) {
    event.preventDefault()
    if (!ready) return
    busy = true
    failure = ''
    try {
      onChecked(await remoteFix(fixBody(form, fingerprint, offer, password)))
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      password = ''
      busy = false
    }
  }
</script>

{#if !open}
  <button class="btn green sm" type="button" onclick={() => (open = true)}>Install it for me</button>
{:else}
  <form class="fix" onsubmit={install} novalidate>
    <p class="muted">{fixWhat(offer)} {needsPassword ? 'Type the password; it is used once and not saved.' : 'It needs no password.'}</p>
    {#if needsPassword}<SecretField label={fixPasswordLabel(form)} name="sudo-password" bind:value={password} />{/if}
    {#if busy}<p class="muted" role="status">Installing… this can take a few minutes.</p>{/if}
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="row">
      <button class="btn line sm" type="button" disabled={busy} onclick={() => { open = false; password = ''; failure = '' }}>Cancel</button>
      <button class="btn green sm" type="submit" disabled={!ready}>{busy ? 'Installing…' : 'Install'}</button>
    </div>
  </form>
{/if}

<style>
  .fix { margin-top: 8px; padding: 10px 12px; border: 1px solid var(--gray); background: var(--white); font-family: var(--sans, inherit); }
  .fix p { margin: 0 0 6px; font-size: 13px; }
  .row { display: flex; justify-content: flex-end; gap: 8px; margin-top: 10px; }
  .bad { color: #d92d20; }
  button.sm { margin-top: 6px; }
</style>
