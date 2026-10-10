<script>
  import Icon from '../Icon.svelte'
  import AuthShell from './AuthShell.svelte'
  import RuviHero from '../RuviHero.svelte'

  let {
    googleConfigured = null,
    registrationCapacity = null,
    bootError = '',
    onRetry,
  } = $props()
</script>

<AuthShell labelledby="login-title">
  <RuviHero />
  <h1 id="login-title">Sign in to Chat</h1>
  <p>Pick up a conversation with your bots and see what their computers are doing.</p>
  {#if registrationCapacity?.registrationsOpen === false}
    <div class="environment-notice" role="status">
      New registrations are temporarily paused because server storage capacity is unavailable. Existing users can still sign in.
      <button class="text-button" onclick={onRetry}>Check capacity again</button>
    </div>
  {/if}
  {#if googleConfigured === false}
    <div class="error-box" role="status">
      Google sign-in is being configured. Please check back shortly.
      <button class="text-button" onclick={onRetry}>Check again</button>
    </div>
  {:else}
    <a class="google-button" href="/auth/google">
      <svg width="19" height="19" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M21.6 12.23c0-.71-.06-1.39-.18-2.05H12v3.88h5.38a4.6 4.6 0 0 1-2 3.02v2.51h3.24c1.9-1.75 2.98-4.33 2.98-7.36ZM12 22c2.7 0 4.96-.9 6.62-2.41l-3.24-2.51c-.9.6-2.04.96-3.38.96-2.6 0-4.81-1.76-5.6-4.13H3.06v2.59A10 10 0 0 0 12 22ZM6.4 13.91a6 6 0 0 1 0-3.82V7.5H3.06a10 10 0 0 0 0 9l3.34-2.59ZM12 5.96c1.47 0 2.79.5 3.82 1.49l2.87-2.87A9.62 9.62 0 0 0 12 2a10 10 0 0 0-8.94 5.5l3.34 2.59C7.19 7.72 9.4 5.96 12 5.96Z" /></svg>
      Continue with Google
      <Icon name="chevron" size={17} />
    </a>
  {/if}
  <div class="login-security"><Icon name="shield" size={16} /><span>Your bots. Your private workspace.</span></div>
  {#if bootError}
    <div class="error-box" role="alert">{bootError}<button class="text-button" onclick={onRetry}>Try again</button></div>
  {/if}
  {#snippet footer()}<span>Ruvio</span><span class="footer-tagline">Private conversations · Connected computers</span>{/snippet}
</AuthShell>

<style>
  .google-button { width: 100%; min-height: 48px; justify-content: flex-start; padding: 12px 20px; font-size: 15px; }
  .google-button > :global(svg:last-child) { margin-left: auto; }
  .login-security { display: flex; align-items: center; justify-content: center; gap: 7px; margin-top: 18px; color: var(--text-2); font: 13px/1.5 var(--font); }
  .environment-notice { margin: 0 0 16px; }
  @media (max-width: 520px) { .footer-tagline { display: none; } }
</style>
