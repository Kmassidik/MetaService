<script>
  let { view, onView } = $props()
</script>

<header class="bar">
  <div class="brand"><span class="mark" aria-hidden="true">M</span><strong>MetaService</strong></div>
  <nav class="tabs" aria-label="Sections">
    <button type="button" class:on={view === 'machines'} aria-current={view === 'machines' ? 'page' : undefined} onclick={() => onView('machines')}>Machines</button>
    <button type="button" class:on={view === 'scan'} aria-current={view === 'scan' ? 'page' : undefined} onclick={() => onView('scan')}>Find machines</button>
  </nav>
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
  .tabs { display: flex; gap: 4px; padding: 3px; background: var(--surface-2); border: 1px solid var(--line); border-radius: 10px; }
  .tabs button { border: 0; background: transparent; min-height: 32px; padding: 0 12px; border-radius: 8px; font-weight: 600; color: var(--muted); }
  .tabs button.on { background: var(--surface); color: var(--ink); box-shadow: var(--shadow); }
  @media (max-width: 700px) { .bar { flex-wrap: wrap; } .tabs { order: 3; width: 100%; } .tabs button { flex: 1; } }
</style>
