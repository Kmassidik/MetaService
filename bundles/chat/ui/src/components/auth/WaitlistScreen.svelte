<script>
  import Icon from '../Icon.svelte'
  import AuthShell from './AuthShell.svelte'
  import RuviHero from '../RuviHero.svelte'

  let {
    firstName = '',
    inviteCode = $bindable(''),
    inviteError = '',
    inviteSaving = false,
    loggingOut = false,
    onSubmit,
    onLogout,
  } = $props()
</script>

<AuthShell labelledby="waitlist-title">
  <RuviHero pose="waitlist" />
  <h1 id="waitlist-title">Thanks, {firstName} — you're on the waitlist</h1>
  <p>Ruvio is invite-only while we grow. We'll let you in as soon as a spot opens. Have an invite code? Enter it to get in right away.</p>
  <form onsubmit={onSubmit}>
    <label class="form-label" for="invite-code">Invite code</label>
    <input
      id="invite-code"
      class="form-input"
      bind:value={inviteCode}
      maxlength="40"
      placeholder="RUV-XXXX-XXXX"
      autocomplete="off"
      autocapitalize="characters"
      spellcheck="false"
    />
    {#if inviteError}<div class="error-box" role="alert">{inviteError}</div>{/if}
    <button class="primary-button submit" type="submit" disabled={inviteSaving || !inviteCode.trim()}>
      {inviteSaving ? 'Checking…' : 'Get in'}<Icon name="chevron" size={16} />
    </button>
  </form>
  <button class="text-button signout" onclick={onLogout} disabled={loggingOut}>Sign out</button>
</AuthShell>

<style>
  .form-input { min-height: 46px; font-size: 15px; }
  .submit { width: 100%; min-height: 46px; margin-top: 16px; font-size: 15px; }
  .signout { display: block; margin: 20px auto 0; color: var(--text-2); font-weight: 500; }
</style>
