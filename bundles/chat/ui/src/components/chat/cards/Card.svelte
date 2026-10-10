<script>
  // One shared card style for every in-chat request.
  let { label = '', title = '', reason = '', children, actions } = $props()
</script>

<div class="card" role="group" aria-label={label || title || 'Action needed'}>
  {#if title}<p class="card-title">{title}</p>{/if}
  {#if reason}<p class="card-reason">{reason}</p>{/if}
  {@render children?.()}
  {#if actions}<div class="card-actions">{@render actions()}</div>{/if}
</div>

<style>
  .card {
    position: relative; display: grid; gap: 10px;
    width: fit-content; min-width: min(360px, 100%); max-width: min(560px, 100%);
    margin: 4px 0; padding: 14px;
    border-radius: var(--radius-card); background: var(--bubble); color: var(--text);
  }
  .card-title { margin: 0; font: 500 var(--fs-message)/var(--lh-message) var(--font); overflow-wrap: anywhere; }
  .card-reason { margin: -4px 0 0; color: var(--text-2); font: 400 14px/1.45 var(--font); overflow-wrap: anywhere; }
  .card-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
  .card-actions:empty { display: none; }
  .card-actions :global(.primary-button) { min-height: 36px; padding: 7px 16px; }
  /* The quiet secondary action: readable but clearly less important than the black pill. */
  .card :global(.card-quiet) {
    min-height: 36px; padding: 7px 14px; border: 0; border-radius: var(--radius-pill);
    background: transparent; color: var(--text-2); font: 500 14px/1.4 var(--font); cursor: pointer;
  }
  .card :global(.card-quiet:hover:not(:disabled)) { background: var(--tint-hover); color: var(--text); }
  .card :global(.card-row) {
    display: flex; align-items: center; gap: 10px; width: 100%; min-height: 44px; padding: 10px 12px;
    border: 1px solid transparent; border-radius: 12px; background: var(--page); color: var(--text);
    font: 400 var(--fs-message)/1.35 var(--font); text-align: left;
  }
</style>
