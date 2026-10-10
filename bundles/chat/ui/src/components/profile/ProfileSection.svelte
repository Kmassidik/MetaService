<script>
  // A titled group: the title sits on the gray sheet, the content in one white card.
  import SavedTick from './SavedTick.svelte'

  let { title, note = '', saved = false, children } = $props()
</script>

<section class="profile-section">
  <h3>{title}<SavedTick shown={saved} /></h3>
  <div class="profile-card">{@render children()}</div>
  {#if note}<p class="profile-section-note">{note}</p>{/if}
</section>

<style>
  .profile-section { display: grid; gap: 6px; }
  h3 { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 0 14px; color: var(--text-2); font: 500 var(--fs-preview)/1.3 var(--font); }
  .profile-card {
    display: grid;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-card);
    background: var(--page);
    overflow: hidden;
  }
  /* Extra specificity so row components that reset their own border still get the divider. */
  .profile-section .profile-card > :global(* + *) { border-top: 1px solid var(--hairline); }
  .profile-section-note { padding: 0 14px; color: var(--text-2); font: 400 var(--fs-time)/1.45 var(--font); }
</style>
