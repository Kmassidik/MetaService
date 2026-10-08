<script>
  let { googleReady } = $props()
</script>

<main class="wrap">
  <section class="card">
    <div class="mark" aria-hidden="true">M</div>
    <h1>MetaService</h1>
    <p class="muted">Manage your machines and the VMs on them.</p>
    {#if googleReady}
      <a class="btn primary" href="/auth/login">Sign in with Google</a>
    {:else}
      <p class="notice" role="status">Google sign-in is not set up on this Root yet. Add the Google client details to the Root's env file, then restart it.</p>
    {/if}
  </section>
</main>

<style>
  .wrap { min-height: 100svh; display: grid; place-items: center; padding-block: 24px; }
  .card {
    width: min(420px, 100%);
    display: grid;
    justify-items: start;
    gap: 14px;
    padding: 32px;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 14px;
    box-shadow: var(--shadow);
  }
  .mark {
    width: 44px;
    height: 44px;
    border-radius: 11px;
    display: grid;
    place-items: center;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 800;
    font-size: 22px;
  }
  h1 { font-size: 26px; letter-spacing: -0.01em; }
  .notice { padding: 12px 14px; border-radius: 8px; background: var(--warn-bg); color: var(--warn); }
</style>
