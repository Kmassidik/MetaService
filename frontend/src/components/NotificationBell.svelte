<script lang="ts">
  // The bell in the top band: a link to the Notifications page with the number of unread ones on it. Draws no number for zero or while the count is unknown.
  import { NOTIFICATIONS_HREF, badgeText, bellLabel } from '../lib/notifications.ts'
  import { bell } from '../lib/notificationsStore.svelte.ts'

  const badge = $derived(badgeText(bell.unread))
</script>

<a class="bell" href={NOTIFICATIONS_HREF} aria-label={bellLabel(bell.unread)} data-testid="bell">
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 17V11a6 6 0 0 1 12 0v6l2 2H4z M10 21h4" /></svg>
  {#if badge}<span class="count" data-testid="bell-count">{badge}</span>{/if}
</a>

<style>
  .bell { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); display: inline-flex; align-items: center; gap: 4px; color: inherit; padding: 4px 6px; text-decoration: none; }
  .bell:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; }
  svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
  .count { min-width: 18px; padding: 1px 5px; background: var(--danger); color: var(--inverse-text); font-size: 10px; line-height: 1.4; text-align: center; letter-spacing: 0; border-radius: 9px; }
</style>
