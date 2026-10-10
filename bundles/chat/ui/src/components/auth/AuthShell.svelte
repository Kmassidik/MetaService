<script>
  import Brand from '../Brand.svelte'

  /** Shared frame for the branded pre-workspace screens (login, onboarding, waitlist). */
  let { labelledby, wide = false, children, footer } = $props()
</script>

<main class="auth-shell">
  <header class="auth-header">
    <a href="/" class="brand" aria-label="Ruvio home"><Brand /></a>
  </header>
  <div class="auth-content">
    <section class="auth-card" class:wide aria-labelledby={labelledby}>
      {@render children()}
    </section>
  </div>
  {#if footer}<footer class="auth-footer">{@render footer()}</footer>{/if}
</main>

<style>
  .auth-shell { min-height: 100dvh; display: flex; flex-direction: column; background: var(--page); overflow-y: auto; }
  .auth-header { height: 68px; flex-shrink: 0; display: flex; align-items: center; padding: 0 28px; }
  .auth-header :global(.wordmark) { font: 600 17px/1 var(--font); }
  .auth-content { flex: 1; display: flex; align-items: center; justify-content: center; padding: 32px 24px 64px; }
  .auth-card { width: 100%; max-width: 380px; }
  .auth-card.wide { max-width: 640px; }
  .auth-card :global(h1) { font: 600 28px/1.25 var(--font); color: var(--text); }
  .auth-card :global(h1 + p) { margin: 12px 0 28px; color: var(--text-2); font: 15px/1.55 var(--font); }
  .auth-card :global(.ruvi ~ h1), .auth-card :global(.ruvi ~ h1 + p) { text-align: center; }
  .auth-footer { display: flex; justify-content: space-between; gap: 16px; padding: 18px 28px; color: var(--text-2); font: 13px/1.5 var(--font); }
  @media (max-width: 520px) {
    .auth-header { padding: 0 20px; }
    .auth-content { align-items: flex-start; padding: 24px 20px 48px; }
    .auth-card :global(h1) { font-size: 25px; }
    .auth-footer { padding: 16px 20px; }
  }
</style>
