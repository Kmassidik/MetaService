<script>
  import hello from '../assets/brand/ruvi.webp'
  import waitlist from '../assets/brand/ruvi-waitlist.webp'
  import settingUp from '../assets/brand/ruvi-setting-up.webp'

  /** Ruvi, the Ruvio mascot, above a heading. Each pose keeps its file's pixel size for layout. */
  const POSES = {
    hello: { src: hello, width: 563, height: 640 },
    waitlist: { src: waitlist, width: 626, height: 640 },
    'setting-up': { src: settingUp, width: 640, height: 639 },
  }

  // `hero` sits above a heading; `inline` is small art beside a line of text, with no spacing of its own.
  let { pose = 'hello', width = 150, variant = 'hero' } = $props()

  const art = $derived(POSES[pose] || POSES.hello)
</script>

<img class="ruvi {variant}" src={art.src} alt="" {width} height={Math.round(width * art.height / art.width)} decoding="async" />

<style>
  .ruvi { display: block; height: auto; margin: 0 auto 22px; }
  @media (prefers-reduced-motion: no-preference) {
    .ruvi { animation: ruvi-pop 0.6s cubic-bezier(0.2, 0.9, 0.3, 1.2) both; }
  }
  @keyframes ruvi-pop { from { opacity: 0; transform: translateY(8px) scale(0.94); } }
  .ruvi.inline { margin: 0; flex-shrink: 0; }
  @media (max-width: 520px) { .ruvi.hero { width: 116px; margin-bottom: 16px; } }
</style>
