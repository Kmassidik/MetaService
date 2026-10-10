<script>
  // The bot is about to say something: a grey bubble with three softly pulsing dots.
  const DOTS = 3
</script>

<div class="typing" role="status" aria-label="Typing">
  {#each { length: DOTS } as _, index (index)}<span style:--dot={index}></span>{/each}
</div>

<style>
  .typing { display: inline-flex; align-self: flex-start; width: fit-content; gap: 5px; align-items: center; margin-top: 4px; padding: 14px 16px; border-radius: var(--radius-bubble); background: var(--bubble); }
  .typing span { width: 7px; height: 7px; border-radius: 50%; background: var(--text-3); opacity: .35; }
  @media (prefers-reduced-motion: no-preference) {
    .typing span { animation: typing-pulse 1s ease-in-out infinite; animation-delay: calc(var(--dot) * 160ms); }
  }
  @keyframes typing-pulse { 40% { opacity: 1; transform: translateY(-2px); } }
</style>
