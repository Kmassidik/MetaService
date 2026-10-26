<script module lang="ts">
  export type MarkKind = 'ready' | 'blocking' | 'optional' | 'waiting' | 'running'
</script>

<script lang="ts">
  // The mark in front of a row. Every kind has its own SHAPE, so it never relies on colour: a circle with a tick, a square with a cross
  // (needs fixing), a triangle with an exclamation (a warning: this works, but something extra is missing), a dotted circle, a turning ring.
  const WORDS: Record<MarkKind, string> = { ready: 'Ready', blocking: 'Needs fixing', optional: 'Not needed to add, but missing', waiting: 'Waiting', running: 'Running' }

  let { kind, word = WORDS[kind] }: { kind: MarkKind; word?: string } = $props()
</script>

<span class="mark {kind}">
  {#if kind === 'running'}
    <span class="spin" aria-hidden="true"></span>
  {:else}
    <svg viewBox="0 0 22 22" aria-hidden="true">
      {#if kind === 'ready'}
        <circle cx="11" cy="11" r="9.5" fill="none" stroke="currentColor" stroke-width="2" />
        <path d="M6.5 11.5l3 3 6-6.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" />
      {:else if kind === 'waiting'}
        <circle cx="11" cy="11" r="9.5" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="1 4" stroke-linecap="round" />
      {:else if kind === 'optional'}
        <path d="M11 2.4 20 18.6H2z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" />
        <path d="M11 8.2v4.6" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
        <circle cx="11" cy="15.6" r="1.05" fill="currentColor" />
      {:else}
        <rect x="1.5" y="1.5" width="19" height="19" rx="4" fill="none" stroke="currentColor" stroke-width="2" />
        <path d="M7 7l8 8M15 7l-8 8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" />
      {/if}
    </svg>
  {/if}
  <span class="sr-only">{word}: </span>
</span>

<style>
  .mark { flex: none; width: 22px; height: 22px; display: inline-grid; place-items: center; }
  svg { width: 22px; height: 22px; display: block; }
  .ready { color: var(--ok); }
  .blocking { color: var(--danger); }
  .optional { color: var(--warn); }
  .waiting { color: var(--m50); }
  .spin { width: 22px; height: 22px; border: 3px solid var(--line); border-top-color: var(--ok); border-radius: 50%; animation: turn 0.9s linear infinite; }
  @keyframes turn { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .spin { animation: none; border-style: dotted; border-top-color: var(--ok); } }
</style>
