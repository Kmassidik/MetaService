<script>
  let { email, onSignOut } = $props()
</script>

<header class="bar">
  <div class="brand"><span class="mark" aria-hidden="true">M</span><strong>MetaService</strong></div>
  <div class="who">
    <span class="muted email">{email}</span>
    <button class="btn" type="button" onclick={onSignOut}>Sign out</button>
  </div>
</header>

<style>
  .bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding-block: 16px;
    padding-top: max(16px, env(safe-area-inset-top));
  }
  .brand { display: flex; align-items: center; gap: 10px; font-size: 18px; }
  .mark {
    width: 30px;
    height: 30px;
    border-radius: 8px;
    display: grid;
    place-items: center;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 800;
  }
  .who { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .email { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 28ch; }
  @media (max-width: 560px) { .email { display: none; } }
</style>
