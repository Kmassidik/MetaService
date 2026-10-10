<script>
  /** One grouped card of Settings rows: an optional title above, an optional note below. */
  let { title = '', note = '', action = undefined, children } = $props()
</script>

<section class="settings-group" aria-label={title || undefined}>
  {#if title || action}
    <div class="group-head">
      {#if title}<h3>{title}</h3>{/if}
      {@render action?.()}
    </div>
  {/if}
  <div class="group-card">{@render children()}</div>
  {#if note}<p class="group-note">{note}</p>{/if}
</section>

<style>
  .settings-group { margin-top: 22px; }
  .settings-group:first-child { margin-top: 0; }
  .group-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 24px; margin: 0 4px 6px 14px; }
  h3 { color: var(--text-2); font: 500 var(--fs-time)/1.3 var(--font); }
  .group-card { overflow: hidden; border-radius: var(--radius-card); background: var(--group); }
  /* A hairline between rows, inset from the left like iOS Settings. */
  .group-card > :global(*) { position: relative; }
  .group-card > :global(* + *::before) { content: ''; position: absolute; top: 0; left: 14px; right: 0; height: 1px; background: var(--group-line); }
  .group-note { margin: 7px 14px 0; color: var(--text-2); font: 400 var(--fs-time)/1.45 var(--font); }
</style>
