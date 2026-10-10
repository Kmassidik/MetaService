<span class="desk-pulse" aria-hidden="true"></span>

<style>
  .desk-pulse {
    display: block;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--brand-green-d);
    animation: desk-pulse 1.6s ease-in-out infinite;
  }
  @keyframes desk-pulse {
    0%, 100% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--brand-green) 45%, transparent); transform: scale(1); }
    50% { box-shadow: 0 0 0 10px color-mix(in srgb, var(--brand-green) 0%, transparent); transform: scale(.9); }
  }
</style>
