<script lang="ts">
  // "Install it for me", under a cross the parent can fix itself: a button, then a password field. The password goes to the parent in one request and is forgotten as soon as it is answered.
  // It draws into the grid of its row: the button in the action column, the form across the text and action columns.
  import SecretField from '../SecretField.svelte'
  import { ApiError, remoteFix } from '../../lib/api.ts'
  import { fixBody, fixButtonLabel, fixNeedsPassword, fixPasswordLabel, fixWhat } from '../../lib/remote.ts'
  import type { ConnectForm, InstallOffer, VerifyResult } from '../../lib/types.ts'

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

  function cancel() {
    open = false
    password = ''
    failure = ''
  }
</script>

{#if !open}
  <span class="act"><button class="offer" type="button" onclick={() => (open = true)}>{fixButtonLabel(offer)}</button></span>
{:else}
  <form class="fix wide" onsubmit={install} novalidate>
    <p class="what">{fixWhat(offer)}</p>
    {#if needsPassword}
      <SecretField label={fixPasswordLabel(form)} name="sudo-password" bind:value={password} />
      <p class="hint">Typed once, never saved. It is used for this one install, then forgotten.</p>
    {:else}
      <p class="hint">It needs no password.</p>
    {/if}
    {#if busy}<p class="hint" role="status">Installing… this can take a few minutes.</p>{/if}
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="buttons">
      <button class="btn line sm" type="button" disabled={busy} onclick={cancel}>Cancel</button>
      <button class="btn green sm" type="submit" disabled={!ready}>{busy ? 'Installing…' : 'Install'}</button>
    </div>
  </form>
{/if}

<style>
  .act { grid-column: 2; margin-top: 8px; }
  .wide { grid-column: 2 / -1; }
  .offer { padding: 6px 12px; background: transparent; color: var(--text); border: 1px solid var(--line-strong); font-family: var(--sans); font-size: 13px; font-weight: 700; min-height: 36px; cursor: pointer; }
  .offer:focus-visible, .buttons :global(.btn:focus-visible) { outline: 3px solid var(--focus); outline-offset: 2px; }
  .fix { margin-top: 10px; padding: 10px 12px; border: 1px solid var(--line); background: var(--surface); }
  .fix :global(.field) { margin-bottom: 4px; }
  p { margin: 0 0 6px; font-size: 13px; overflow-wrap: anywhere; }
  .hint { font-size: 12px; color: var(--m50); }
  .bad { color: var(--danger); }
  .buttons { display: flex; justify-content: flex-end; gap: 8px; margin-top: 10px; }
</style>
