<script>
  import ruviUrl from '../assets/brand/ruvi.webp'

  /** First paint while the session and workspace load: Ruvi, a short line and a slim bar. */
  const RUVI_WIDTH = 180
  const HEIGHT_PER_WIDTH = 640 / 563 // pixel size of ruvi.webp
</script>

<main class="boot" role="status" aria-live="polite">
  <img class="boot-ruvi" src={ruviUrl} alt="" width={RUVI_WIDTH} height={Math.round(RUVI_WIDTH * HEIGHT_PER_WIDTH)} />
  <p>Opening your workspace…</p>
  <div class="boot-bar" aria-hidden="true"><span></span></div>
</main>

<style>
  .boot { min-height: 100dvh; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; padding: 24px; background: var(--page); }
  .boot-ruvi { display: block; height: auto; margin-bottom: 10px; }
  .boot p { margin: 0; color: var(--text-2); font: 500 15px/1.5 var(--font); }
  .boot-bar { position: relative; width: 160px; height: 4px; overflow: hidden; border-radius: var(--radius-pill); background: var(--bubble); }
  .boot-bar span { position: absolute; inset: 0 auto 0 0; width: 40%; border-radius: inherit; background: var(--ink); animation: boot-slide 1.4s ease-in-out infinite; }
  @keyframes boot-slide { from { transform: translateX(-100%); } to { transform: translateX(250%); } }
  @media (prefers-reduced-motion: no-preference) {
    .boot-ruvi { animation: boot-bob 2.4s ease-in-out infinite; }
  }
  @keyframes boot-bob { 50% { transform: translateY(-8px); } }
  @media (prefers-reduced-motion: reduce) { .boot-bar span { animation: none; } }
  @media (max-width: 520px) { .boot-ruvi { width: 140px; } }
</style>
